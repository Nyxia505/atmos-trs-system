import com.android.build.gradle.LibraryExtension
import org.gradle.api.Project
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

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
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            if (namespace.isNullOrBlank()) {
                namespace = project.safeNamespace()
            }
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

fun Project.safeNamespace(): String {
    val groupValue = group.toString()
    if (groupValue.isNotBlank() && groupValue != "unspecified") {
        return groupValue
            .replace(Regex("[^A-Za-z0-9_.]"), "_")
            .trim('.')
            .ifBlank { "com.atmos.generated.${name.sanitizedSegment()}" }
    }
    return "com.atmos.generated.${name.sanitizedSegment()}"
}

fun String.sanitizedSegment(): String {
    return lowercase()
        .replace(Regex("[^a-z0-9_]"), "_")
        .replace(Regex("_+"), "_")
        .trim('_')
        .ifBlank { "module" }
}
