allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = "../build"
subprojects {
    project.buildDir = "${rootProject.buildDir}/${project.name}"
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 👇 الكود الهندسي السحري لإجبار جميع المكتبات (مثل file_picker) على التوافق مع إصدار 36
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty('android')) {
            project.android {
                if (compileSdkVersion == 34 || compileSdkVersion < 36) {
                    compileSdkVersion 36
                }
            }
        }
    }
}

tasks.register("clean", Delete) {
    delete rootProject.buildDir
}
