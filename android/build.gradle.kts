allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Некоторые плагины собраны с compileSdk 34/35, а их зависимости (androidx,
// flutter_plugin_android_lifecycle) требуют 36+. Поднимаем compileSdk у плагинов;
// сам :app пропускаем, у него свой compileSdk в app/build.gradle.kts.
// Проверка `is` вместо `as`: если у модуля другой тип расширения, сборка не падает.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (project.name != "app" && androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
