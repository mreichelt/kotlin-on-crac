# Talk: Kotlin on CRaC – new JVM features to speed things up

Talk for [Droidcon Berlin 2025](https://berlin.droidcon.com/speakers/marc-reichelt).

- Slides: coming shortly
- Video recording: will be available a few weeks after the conference

## Talk Description

What if we could drastically improve the JVM startup time? What if we could start a Kotlin-powered backend in milliseconds?

Let's explore some exciting new JVM features like the experimental [CRaC](https://openjdk.org/projects/crac/) (Coordinated Restore at Checkpoint) and [JEP 483](https://openjdk.org/jeps/483) (Ahead-of-Time Class Loading & Linking) from Project Leyden, a feature of JDK 24! How fast are they, and how are they different from GraalVM and Kotlin Native?
Plus, let's have a look at [JEP 515](https://openjdk.org/jeps/515) (Ahead-of-Time Method Profiling) from the brand new JDK 25!

Finally, let's go completely wild, and experiment with a crazy idea: Let's see if we can apply these technologies to make our Gradle unit test workflows in Android projects faster as well!

## Contact

- [BlueSky: mreichelt](https://bsky.app/profile/mreichelt.bsky.social)
- [Mastodon: mastodon.social/@mreichelt](https://mastodon.social/@mreichelt)

## Notes

### CRaC (Coordinated Restore at Checkpoint)

Lets us create a checkpoint of a running JVM, and lets us restore it later. Coordinated means that the application needs to be aware of when checkpoint+restore happen, because all files and network connections must be closed for the checkpoint to be created.

#### Using CRaC

Start your application. Use the `-XX:CRaCCheckpointTo=` parameter to tell CRaC in which directory to store its files, `crac-files` in this case:

```console
java -XX:CRaCCheckpointTo=crac-files -jar path/to/app.jar
```

With this we started the training phase. We'll warm up the application until it is hot enough, meaning that all important classes important for production have been loaded and its code has been JIT-compiled. Depending on the app, this could take a few seconds, minutes, or even hours for really large apps.

For a backend application, this could mean triggering HTTP calls until we've reached a desired performance.

Now, in a second shell, let's tell CRaC to create the checkpoint (tip: run `jcmd` to see all running JVM apps if you're unsure):

```console
jcmd path/to/app.jar JDK.checkpoint
```

If successful, the application will quit, and all files will have been stored to `crac-files`.

Now, let's profit, and start the application from the stored checkpoint - starting in a few milliseconds for most apps, in some cases even 100x faster than a classic cold-start! (no, that's not a typo - see the [benchmark in the CRaC docs](https://github.com/CRaC/docs/tree/master?tab=readme-ov-file#results))

```console
java -XX:CRaCRestoreFrom=crac-files
```

#### Setup a Docker image for CRaC

Because the CRaC feature only works on Linux today (September 2025), it can be helpful to setup a Docker image with a CRaC-enabled JDK, for example if you're using a Mac. Use [Dockerfile.crac](Dockerfile.crac) to setup a [CRaC-enabled Azul Zulu JDK](https://www.azul.com/downloads/?package=jdk-crac#zulu):

```console
docker build --tag crac --file Dockerfile.crac .
```

Then, you can start an interactive shell in the folder where your JVM application is located. This will mount your current host working directory to the path `/app` inside the guest image, and forward the `8080` port (to access a backend from the host):

```console
cd your-jvm-app
docker run --privileged --rm -it --name crac --volume .:/app -p 8080:8080 --entrypoint /bin/bash crac

# inside the interactive shell:
cd /app
```

Finally, you can start a session (or more) into the same container. In this second shell, you'll be able to run the `jcmd … JDK.checkpoint` command mentioned above:

```console
docker exec -it -u root crac /bin/bash
```

#### Configure your app for CRaC

The checkpoint and restore are coordinated. In order to create a checkpoint, all open files and network connections have to be closed, or otherwise the JVM will throw an exception when attempting to create the checkpoint.

To do this, you can add the [org.crac:crac](https://mvnrepository.com/artifact/org.crac/crac) dependency, and implement the [Resource](https://javadoc.io/doc/org.crac/crac/latest/index.html) interface, using `beforeCheckpoint` to get notified when the checkpoint is triggered, and `afterRestore` to get notified when the restore is triggered. Finally, you can call `Core.getGlobalContext().register(YourResource())` to make CRaC aware of your Resource. I highly recommend the talk [Java on CRaC by Simon Ritter](https://youtu.be/bWmuqh6wHgE?si=v7Cd1_hb0jMbhW_k&t=2190) that explains this nicely.

##### CRaC with Spring Boot

Multiple backend frameworks already support CRaC out of the box, so there's no need to implement a `Resource` yourself.
To make it work with Spring Boot, just add the dependency [org.crac:crac](https://mvnrepository.com/artifact/org.crac/crac) to your application. I had good results by using the [spring-petclinic-kotlin](https://github.com/spring-petclinic/spring-petclinic-kotlin) sample project, adding `implementation("org.crac:crac")` as a dependency and by upgrading the Gradle wrapper to 8.14.x (for JDK 24 support) by running this command twice:

```console
./gradlew wrapper --gradle-version 8.14.3 --distribution-type bin
```

Bonus tip: extract the [Spring Boot JAR as described in the docs](https://docs.spring.io/spring-boot/reference/packaging/efficient.html). It's not strictly necessary for CRaC, but this deployment is more efficient by default, and leads to much better results when using AOTCache or CDS. You'll thank me later!

### AOTCache

In contrast to CRaC, the AOTCache works on all platforms. JDK 24 introduced JEP 483 (Ahead-of-Time Class Loading & Linking), and the brand new JDK 25 introduced JEP 515 (Ahead-of-Time Method Profiling). The newer the JDK, the larger the AOTCache improvements will be!

Start your training run like this:

```console
java -XX:AOTMode=record -XX:AOTConfiguration=app.aotconf -jar app.jar
```

This will create the file `app.aotconf` with information about your training run. I recommend running this on JDK 24 for curiosity, because here it contains just text, so you can have a peek inside. In JDK 25 the content is binary, to also include the method profiling info. Example for a Spring Boot app on JDK 24:

```plain
… thousands of lines …
org/springframework/core/io/support/SpringFactoriesLoader$FactoryInstantiator id: 1336
org/springframework/core/KotlinDetector id: 1337
kotlin/Metadata id: 1338
kotlin/jvm/JvmInline id: 1339
kotlin/reflect/full/KClasses id: 1340
java/lang/Class$AnnotationData id: 1341
…
```

In a second step we will create the actual AOTCache. This will not run the app, but collect all data from the classpath based on the `app.aotconf` data from the training run:

```console
java -XX:AOTMode=create -XX:AOTConfiguration=app.aotconf -XX:AOTCache=app.aot -jar app.jar
```

Finally, to run the application using the new AOTCache:

```console
java -XX:AOTCache=app.aot -jar app.jar
```

In my tests with the spring-petclinic-kotlin project, I got a startup performance improvement of 43% with JDK 24, and 50% improvement with JDK 25. Nice!

Bonus tip: In case something goes wrong, the JVM will just reject the AOTCache and continue with a cold start. That's good for production, because it'll just work, but is not helpful if what you're testing is the actual AOTCache. Just add the `-XX:AOTMode=on` parameter, and the JVM will halt if it could not use the AOTCache:

```console
java -XX:AOTMode=on -XX:AOTCache=app.aot -jar app.jar
```

This was especially helpful in my tests with a changing classpath, because the AOTCache will not work if the classpath is changed too much.

#### AOTCache, simplified

JDK 25 also introduces [JEP 514](https://openjdk.org/jeps/514), which will simplify the two-step process into a single-step invocation. No more need for a temporary `app.aotconf` file, just run:

```console
java -XX:AOTCacheOutput=app.aot -jar app.jar
```

The classic way (first create, then record) still works, and can be helpful in my opinion to understand the process. Especially when running on JDK 24, I found it very helpful to inspect the `app.aotconf` text file!

#### AOTCache with Spring Boot

For using the AOTCache with Spring Boot, it's important to [extract the Spring Boot JAR](https://docs.spring.io/spring-boot/reference/packaging/efficient.html) first. Otherwise many classes will not make it into the AOTCache, and your startup performance will not improve much. Thanks to [Sébastien Deleuze](https://seb.deleuze.fr/) for the tip! Check out [these docs](https://docs.spring.io/spring-boot/reference/packaging/class-data-sharing.html#packaging.class-data-sharing.aot-cache) as well, and the [example-spring-boot](https://github.com/CRaC/example-spring-boot) repo.

### Measure backend startup

In order to measure the time until the first backend call succeeds, use [measure_petclinic.sh](measure_petclinic.sh) with the Java arguments you want to run. This will:

1. Launch a JVM with your provided Java args
2. Continuosly call [http://localhost:8080/owners?lastName=](http://localhost:8080/owners?lastName=) with `curl` until it returns 200 (yep, it's hard-coded)
3. Print the time it took until the first successful call is done
4. Kill the JVM

For example, this is how to measure the same app without, and then with an AOTCache:

```console
$ ./measure_petclinic.sh -jar app.jar
Backend ready in 2469 ms

$ ./measure_petclinic.sh -XX:AOTCache=app.aot -XX:AOTMode=on -jar app.jar
Backend ready in 1412 ms
```
