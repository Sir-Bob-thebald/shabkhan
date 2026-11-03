import java.util.Properties

// Machine-specific settings in android/local.properties (not in version control).
val localProps = Properties().apply {
    val f = file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

allprojects {
    repositories {
        // Flutter engine jars downloaded by hand (with resume) because the
        // mirror resets long downloads; set `engineRepo=` in local.properties.
        // Gradle falls through if a jar is missing.
        localProps.getProperty("engineRepo")?.let { maven(it) }
        // Google Maven is blocked on this network; Aliyun mirrors it.
        maven("https://maven.aliyun.com/repository/google")
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
