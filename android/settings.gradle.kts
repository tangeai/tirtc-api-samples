pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()

        maven {
            url = uri("https://repo-sdk.tange-ai.com/repository/maven-public/")
            val publicMavenUsername = providers.gradleProperty("TIRTC_PUBLIC_MAVEN_USERNAME").orNull
            val publicMavenPassword = providers.gradleProperty("TIRTC_PUBLIC_MAVEN_PASSWORD").orNull
            if (!publicMavenUsername.isNullOrBlank() && !publicMavenPassword.isNullOrBlank()) {
                credentials {
                    username = publicMavenUsername
                    password = publicMavenPassword
                }
            }
        }
    }
}

rootProject.name = "tirtc-api-samples-android"
include(":example")

project(":example").projectDir = file("example")
