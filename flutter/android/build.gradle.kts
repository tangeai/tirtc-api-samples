val tirtcAndroidLocalMavenRepo: String? =
    providers.gradleProperty("TIRTC_FLUTTER_ANDROID_LOCAL_MAVEN").orNull
        ?: run {
            val localPropertiesFile = rootProject.file("local.properties")
            if (!localPropertiesFile.isFile) {
                null
            } else {
                val localProperties = java.util.Properties()
                localPropertiesFile.inputStream().use { stream ->
                    localProperties.load(stream)
                }
                localProperties.getProperty("tirtc.flutter.android.localMaven")?.takeIf { it.isNotBlank() }
            }
        }
        ?: providers.environmentVariable("TIRTC_FLUTTER_ANDROID_LOCAL_MAVEN").orNull

allprojects {
    repositories {
        if (tirtcAndroidLocalMavenRepo != null) {
            maven {
                url = uri(tirtcAndroidLocalMavenRepo)
            }
        }
        google()
        mavenCentral()
        maven {
            url = uri("https://repo-sdk.tange-ai.com/repository/maven-public/")
            credentials {
                username =
                    "tange_user"
                password =
                    "tange_user"
            }
        }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
