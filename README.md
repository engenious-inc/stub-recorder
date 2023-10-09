# Stub-Recorder

## Features
* Supports HTTP and HTTPS protocols.
* Records all network traffic.
* Facilitates playback of recorded network traffic.
* Enables modification of request/response.

## Instalation
Add this Swift Package Manager (SPM) to your project: `https://github.com/engenious-inc/swift-proxy.git`

## Usage
```
lazy var stubRecorder = StubRecorder(
    recordModePath: "/FULL_PATH_TO_PROJECT/StubResources",
    playbackModeRelativePath: "StubResources",
    sslCertPath: cert,
    sslPrivateKeyPath: privateKey,
    scenarioName: testName,
    host: "127.0.0.1",
    port: .random,
    endpoint: "https://PROXY.DESTINATION",
    record: .on,
    stubMutators: []
    logger: logger,
    responseDelayMillis: delayMillis,
    optionalFileExtension: ".json"
)
stubRecorder.start()
```
