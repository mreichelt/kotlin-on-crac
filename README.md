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

Now, in a second shell, let's tell CRaC to create the checkpoint:

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

Finally, you can start one (or more) session into the same container. In this second shell, you'll be able to run the `jcmd … JDK.checkpoint` command mentioned above:

```console
docker exec -it -u root crac /bin/bash
```
