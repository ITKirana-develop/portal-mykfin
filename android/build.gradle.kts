allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Paksa compileSdk 36 untuk SEMUA module Android (termasuk plugin pihak
// ketiga seperti wireguard_flutter yang masih hardcode compileSdk 31 di
// dalam kodenya sendiri). Tanpa ini, checkDebugAarMetadata gagal karena
// dependency androidx modern butuh compileSdk lebih tinggi dari yang
// dideklarasikan si plugin.
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library") ||
            project.plugins.hasPlugin("com.android.application")
        ) {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
                ?.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}