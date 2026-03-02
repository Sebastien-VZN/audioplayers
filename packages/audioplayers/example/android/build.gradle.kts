allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.layout.buildDirectory = rootProject.layout.projectDirectory.dir("../build")

subprojects {
    if (project.name == "app") {
        project.layout.buildDirectory = rootProject.layout.buildDirectory.dir(project.name).get()
    }
}

subprojects {
    project.plugins.withId("com.android.library") {
        project.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            testOptions.unitTests.isIncludeAndroidResources = false
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
