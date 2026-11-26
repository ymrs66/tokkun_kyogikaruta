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
// share_plus 7.x は compileSdk 33 でビルドされるため android-33 プラットフォームを要求する。
// 共有の Android SDK に 33 を追加しなくて済むよう、プラグインの compileSdk を app と同じ 36 に揃える
// （36 未満のものだけ。プラグインの minSdk / targetSdk は変えない）。
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { lib ->
            if ((lib.compileSdk ?: 0) < 36) lib.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
