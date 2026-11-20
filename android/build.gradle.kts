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

    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }

    afterEvaluate {
        extensions.findByName("android")?.let { androidExt ->
            try {
                val compileOptions = androidExt.javaClass.getMethod("getCompileOptions").invoke(androidExt)
                compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java)
                    .invoke(compileOptions, JavaVersion.VERSION_17)
                compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java)
                    .invoke(compileOptions, JavaVersion.VERSION_17)
            } catch (_: Throwable) {
            }
        }

        tasks.matching { task ->
            task.javaClass.name.contains("KotlinCompile")
        }.configureEach {
            try {
                val compilerOptions = javaClass.getMethod("getCompilerOptions").invoke(this)
                val jvmTargetProp = compilerOptions.javaClass.getMethod("getJvmTarget").invoke(compilerOptions)
                val jvm17 = Class.forName("org.jetbrains.kotlin.gradle.dsl.JvmTarget")
                    .getField("JVM_17").get(null)
                jvmTargetProp.javaClass.getMethod("set", Any::class.java).invoke(jvmTargetProp, jvm17)
            } catch (_: Throwable) {
                // Fallback for older kotlinOptions-based plugins.
                try {
                    val kotlinOptions = javaClass.getMethod("getKotlinOptions").invoke(this)
                    kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java)
                        .invoke(kotlinOptions, "17")
                } catch (_: Throwable) {
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
