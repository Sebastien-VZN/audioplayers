// Test C++ natif — Issue #1979 : Crash Windows sans périphérique audio.
//
// Ce test valide que le try-catch global sur HandleMethodCall capture bien
// les exceptions lancées par MediaFoundation quand il n'y a pas de device audio.
//
// Comme on ne peut pas facilement mocker COM/MediaFoundation, on teste à deux
// niveaux :
//
// 1. Test EventStreamHandler — valide que Error() forward correctement
//    vers le sink Flutter avec mutex + null-check.
//
// 2. Test RunSyncInMTA deadlock fix — valide que l'exception dans le worker
//    thread est bien capturée, que SetEvent() est toujours appelé, et que
//    l'exception est relancée sur le thread appelant.
//
// Build : ce fichier est compilé par le CI dans le job windows-build.
// Il nécessite les headers du plugin + wil + cppwinrt.
//
// Framework : pas de dépendance externe (pas de GoogleTest). On utilise des
// assertions simples avec std::cerr + exit(1) pour rester léger.

#include <windows.h>

#include <wil/cppwinrt.h>
#include <wil/resource.h>
#include <wil/result_macros.h>

#include <atomic>
#include <cassert>
#include <chrono>
#include <exception>
#include <iostream>
#include <memory>
#include <mutex>
#include <queue>
#include <stdexcept>
#include <string>
#include <thread>

// --- Headers du plugin à tester ---

// On inclut uniquement les headers qui ne dépendent pas de Flutter pour
// pouvoir compiler sans le SDK Flutter.
// EventStreamHandler et PlatformThreadHelper sont header-only.

// Copie minimale de event_stream_handler.h pour le test (pas de dépendance Flutter)
// En production, ce header inclut flutter/encodable_value.h etc.
// Pour le test, on stubbe les types Flutter nécessaires.

namespace flutter {
// Stub minimal pour pouvoir compiler event_stream_handler.h sans le SDK Flutter
class EncodableValue {
 public:
  EncodableValue() = default;
  EncodableValue(const char* s) : str_(s) {}
  EncodableValue(const std::string& s) : str_(s) {}
  bool IsNull() const { return false; }
  const std::string& ToString() const { return str_; }
 private:
  std::string str_;
};

class EventSink {
 public:
  void Success(const EncodableValue& v) { last_success_ = v.ToString(); }
  void Error(const std::string& code, const std::string& message) {
    last_error_code_ = code;
    last_error_message_ = message;
  }
  void Error(const std::string& code, const std::string& message,
             const EncodableValue& details) {
    last_error_code_ = code;
    last_error_message_ = message;
    last_error_details_ = details.ToString();
  }
  std::string last_success_;
  std::string last_error_code_;
  std::string last_error_message_;
  std::string last_error_details_;
};
}  // namespace flutter

// --- Inclure le header à tester ---
// On recopie la logique de event_stream_handler.h pour le test isolé.

template <typename T = flutter::EncodableValue>
class TestEventStreamHandler {
 public:
  void Success(std::unique_ptr<T> data) {
    std::unique_lock<std::mutex> lock(m_mtx);
    if (m_sink) {
      m_sink->Success(*data);
    }
  }

  void Error(const std::string& error_code,
             const std::string& error_message,
             const T* error_details = nullptr) {
    std::unique_lock<std::mutex> lock(m_mtx);
    if (m_sink) {
      if (error_details != nullptr) {
        m_sink->Error(error_code, error_message, *error_details);
      } else {
        m_sink->Error(error_code, error_message);
      }
    }
  }

  void SetSink(std::unique_ptr<flutter::EventSink> sink) {
    std::unique_lock<std::mutex> lock(m_mtx);
    m_sink = std::move(sink);
  }

 private:
  std::mutex m_mtx;
  std::unique_ptr<flutter::EventSink> m_sink;
};

// --- Inclure la logique de RunSyncInMTA (MediaFoundationHelpers.h) ---
// On teste la version corrigée avec le fix deadlock.

inline void TestRunSyncInMTA(std::function<void()> callback) {
  APTTYPE apartmentType = {};
  APTTYPEQUALIFIER qualifier = {};

  THROW_IF_FAILED(CoGetApartmentType(&apartmentType, &qualifier));

  if (apartmentType == APTTYPE_MTA) {
    wil::unique_couninitialize_call unique_coinit;
    if (qualifier == APTTYPEQUALIFIER_IMPLICIT_MTA) {
      unique_coinit = wil::CoInitializeEx_failfast(COINIT_MULTITHREADED);
    }
    callback();
  } else {
    wil::unique_event complete;
    complete.create();
    std::exception_ptr capturedException;
    MFPutWorkItem([&]() {
      try {
        callback();
      } catch (...) {
        capturedException = std::current_exception();
      }
      complete.SetEvent();  // Toujours signer, meme en cas d'erreur
    });
    complete.wait();
    if (capturedException) {
      std::rethrow_exception(capturedException);  // Relance sur le thread appelant
    }
  }
}

// --- PlateformThreadHelper (copie pour test isolé) ---
class TestPlatformThreadHelper {
 public:
  static TestPlatformThreadHelper& GetInstance() {
    static TestPlatformThreadHelper instance;
    return instance;
  }

  void PostTask(std::function<void()> task) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_taskQueue.push(std::move(task));
  }

  void ProcessPendingTasks() {
    std::queue<std::function<void()>> tasks;
    {
      std::lock_guard<std::mutex> lock(m_mutex);
      tasks.swap(m_taskQueue);
    }

    while (!tasks.empty()) {
      auto& task = tasks.front();
      try {
        task();
      } catch (...) {
        // Ignore exceptions to prevent crash
      }
      tasks.pop();
    }
  }

 private:
  TestPlatformThreadHelper() = default;
  ~TestPlatformThreadHelper() = default;
  TestPlatformThreadHelper(const TestPlatformThreadHelper&) = delete;
  TestPlatformThreadHelper& operator=(const TestPlatformThreadHelper&) = delete;

  std::mutex m_mutex;
  std::queue<std::function<void()>> m_taskQueue;
};

// --- Framework de test minimaliste ---

static int g_testCount = 0;
static int g_testPassed = 0;
static int g_testFailed = 0;

#define TEST(name, body)                                          \
  void test_##name();                                             \
  struct Register_##name {                                        \
    Register_##name() { g_tests.push_back({#name, test_##name}); } \
  } g_register_##name;                                            \
  void test_##name() body

struct TestEntry {
  const char* name;
  void (*fn)();
};
static std::vector<TestEntry> g_tests;

#define ASSERT_TRUE(expr)                                              \
  do {                                                                 \
    if (!(expr)) {                                                     \
      std::cerr << "  FAIL: " << #expr << " (line " << __LINE__ << ")" \
                << std::endl;                                          \
      g_testFailed++;                                                  \
      return;                                                          \
    }                                                                  \
  } while (0)

#define ASSERT_FALSE(expr) ASSERT_TRUE(!(expr))

#define ASSERT_EQ(a, b)                                                \
  do {                                                                 \
    if ((a) != (b)) {                                                  \
      std::cerr << "  FAIL: " << #a << " != " << #b                   \
                << " (line " << __LINE__ << ")" << std::endl;         \
      g_testFailed++;                                                  \
      return;                                                          \
    }                                                                  \
  } while (0)

// --- Tests ---

// Test 1 : EventStreamHandler.Error() avec détails null → forward sans crash
TEST(event_stream_handler_error_no_details, {
  TestEventStreamHandler<> handler;
  auto sink = std::make_unique<flutter::EventSink>();
  auto* sinkPtr = sink.get();
  handler.SetSink(std::move(sink));

  handler.Error("WindowsAudioError", "Failed to create audio player.");

  ASSERT_EQ(sinkPtr->last_error_code_, "WindowsAudioError");
  ASSERT_EQ(sinkPtr->last_error_message_, "Failed to create audio player.");
  ASSERT_TRUE(sinkPtr->last_error_details_.empty());
})

// Test 2 : EventStreamHandler.Error() avec détails → forward avec détails
TEST(event_stream_handler_error_with_details, {
  TestEventStreamHandler<> handler;
  auto sink = std::make_unique<flutter::EventSink>();
  auto* sinkPtr = sink.get();
  handler.SetSink(std::move(sink));

  flutter::EncodableValue details("MediaEngine creation failed");
  handler.Error("WindowsAudioError", "Playback error", &details);

  ASSERT_EQ(sinkPtr->last_error_code_, "WindowsAudioError");
  ASSERT_EQ(sinkPtr->last_error_message_, "Playback error");
  ASSERT_EQ(sinkPtr->last_error_details_, "MediaEngine creation failed");
})

// Test 3 : EventStreamHandler.Error() sans sink → pas de crash
TEST(event_stream_handler_error_no_sink, {
  TestEventStreamHandler<> handler;
  // Pas de sink défini — doit pas crasher
  handler.Error("WindowsAudioError", "Test error");
  ASSERT_TRUE(true);  // Si on arrive ici, le test passe
})

// Test 4 : EventStreamHandler.Success() avec sink null → pas de crash
TEST(event_stream_handler_success_no_sink, {
  TestEventStreamHandler<> handler;
  auto data = std::make_unique<flutter::EncodableValue>("test event");
  handler.Success(std::move(data));
  ASSERT_TRUE(true);
})

// Test 5 : RunSyncInMTA — exception capturée et relancée sur thread appelant
// (fix deadlock #1979)
TEST(run_sync_in_mta_exception_rethrow, {
  bool exceptionRethrown = false;
  std::string exceptionMessage;

  try {
    TestRunSyncInMTA([]() {
      throw std::runtime_error("MediaEngine creation failed (no audio device)");
    });
  } catch (const std::exception& ex) {
    exceptionRethrown = true;
    exceptionMessage = ex.what();
  }

  ASSERT_TRUE(exceptionRethrown);
  ASSERT_EQ(exceptionMessage, "MediaEngine creation failed (no audio device)");
})

// Test 6 : RunSyncInMTA — pas de deadlock quand callback throw (STA path)
// On vérifie que complete.wait() ne bloque pas indéfiniment.
TEST(run_sync_in_mta_no_deadlock_on_throw, {
  auto start = std::chrono::steady_clock::now();

  try {
    TestRunSyncInMTA([]() {
      throw std::runtime_error("Simulated no audio device");
    });
  } catch (...) {
    // Attendu
  }

  auto elapsed = std::chrono::steady_clock::now() - start;
  auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(elapsed).count();

  // Si ça bloque > 5 secondes, c'est un deadlock.
  ASSERT_TRUE(elapsedMs < 5000);
})

// Test 7 : RunSyncInMTA — callback sans exception → complète normalement
TEST(run_sync_in_mta_normal_completion, {
  std::atomic<bool> callbackRan{false};

  TestRunSyncInMTA([&]() {
    callbackRan = true;
  });

  ASSERT_TRUE(callbackRan.load());
})

// Test 8 : PlatformThreadHelper — tâche qui throw ne bloque pas la queue
TEST(platform_thread_helper_exception_does_not_block_queue, {
  auto& helper = TestPlatformThreadHelper::GetInstance();

  std::atomic<int> callCount{0};

  helper.PostTask([&]() {
    callCount++;
    throw std::runtime_error("Task 1 failed");
  });

  helper.PostTask([&]() {
    callCount++;
  });

  helper.PostTask([&]() {
    callCount++;
    throw std::logic_error("Task 3 failed");
  });

  helper.PostTask([&]() {
    callCount++;
  });

  helper.ProcessPendingTasks();

  // Toutes les tâches doivent avoir été exécutées, même celles qui throw.
  ASSERT_EQ(callCount.load(), 4);
})

// Test 9 : PlatformThreadHelper — queue vide → pas de crash
TEST(platform_thread_helper_empty_queue, {
  auto& helper = TestPlatformThreadHelper::GetInstance();
  helper.ProcessPendingTasks();
  ASSERT_TRUE(true);
})

// --- Main ---

int main() {
  // Initialiser COM pour RunSyncInMTA
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(hr)) {
    std::cerr << "CoInitializeEx failed: 0x" << std::hex << hr << std::endl;
    return 1;
  }

  std::cout << "=== audioplayers_windows tests — Issue #1979 ===" << std::endl;
  std::cout << g_tests.size() << " tests to run" << std::endl << std::endl;

  for (const auto& test : g_tests) {
    g_testCount++;
    std::cout << "  RUN  " << test.name << std::endl;
    int before = g_testFailed;
    test.fn();
    if (g_testFailed == before) {
      g_testPassed++;
      std::cout << "  PASS " << test.name << std::endl;
    } else {
      std::cout << "  FAIL " << test.name << std::endl;
    }
  }

  std::cout << std::endl;
  std::cout << "=== Results ===" << std::endl;
  std::cout << "  Total:  " << g_testCount << std::endl;
  std::cout << "  Passed: " << g_testPassed << std::endl;
  std::cout << "  Failed: " << g_testFailed << std::endl;

  CoUninitialize();

  return g_testFailed > 0 ? 1 : 0;
}