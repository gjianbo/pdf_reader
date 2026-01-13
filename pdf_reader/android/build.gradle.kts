allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
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

    fun setNamespace() {
        val android = project.extensions.findByName("android") ?: return
        try {
            val getNamespace = android.javaClass.getMethod("getNamespace")
            val namespace = getNamespace.invoke(android)

            if (namespace == null) {
                val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                
                if (project.name == "isar_flutter_libs") {
                    setNamespace.invoke(android, "dev.isar.isar_flutter_libs")
                } else {
                    val manifestFile = project.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val manifestContent = manifestFile.readText()
                        val packageRegex = Regex("package=\"([^\"]+)\"")
                        val match = packageRegex.find(manifestContent)
                        if (match != null) {
                            setNamespace.invoke(android, match.groupValues[1])
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // Ignore errors
        }
    }

    if (project.state.executed) {
        setNamespace()
    } else {
        project.afterEvaluate {
            setNamespace()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
