
# Process Manager Library (`pm.dart`)

This library provides a simple, non-streaming, callback-based service for managing and monitoring command-line processes in Dart. It is designed to be a lightweight and easy-to-use solution for executing external commands and capturing their output.

The core philosophy of this library is to provide the fundamental building blocks for process management, allowing the user to build more complex asynchronous patterns (like streams) on top of a simple, callback-driven API.

### Key Features

-   **Callback-based output handling**: Receive standard output and standard error data as it is generated, without the overhead of `Streams`.
    
-   **Persistent output history**: All standard output and standard error are stored in `List<String>`s, making it easy to access the full history of a process after it has finished.
    
-   **Simple process lifecycle management**: Start, stop, and monitor processes using a unique identifier.
    
-   **Future-based exit code**: A `Future` provides a clean way to handle a process's termination and exit code.
    

### Installation

Since `pm.dart` is a single file, you can simply add it to your project and import it.

```
// In your main.dart or other Dart file
import 'pm.dart';

```

### Usage

#### 1. Initialization

First, create a single instance of the `ProcessManagerService`. This object is designed to be a singleton that can manage multiple processes throughout your application's lifecycle.

```
final ProcessManagerService pm = ProcessManagerService();

```

Remember to call the `dispose()` method when your application is shutting down to ensure all resources are properly released.

#### 2. Starting a Process

The `startProcess` method is the primary way to execute a command. It returns a unique `String` ID for the new process. You can optionally provide callbacks to handle output as it arrives.

The `onStdout` and `onStderr` callbacks are called with each new chunk of output from the process.

**Example:** Using `onStdout` and `onStderr`

```
import 'pm.dart';

Future<void> runPing() async {
  final pm = ProcessManagerService();

  print('Starting ping...');

  // Use the callbacks to print output as it arrives
  final processId = await pm.startProcess(
    'ping -c 5 google.com',
    onStdout: (pmi_data) {
      print('STDOUT: $pmi_data');
    },
    onStderr: (pmi_data) {
      print('STDERR: $pmi_data');
    },
    onExit: (pmi_data) {
      print('Process exited with code: ${pmi_data.exitCode}');
    },
  );
  
  // Clean up the service when done
  pm.dispose();
}

```

#### 3. Stopping a Running Process

You can terminate a running process using its `id` with the `stopProcess` method. This is useful for user-initiated cancellation.

**Example:** Stopping a long-running process

```
import 'pm.dart';

Future<void> runThenStop() async {
  final pm = ProcessManagerService();

  final processId = await pm.startProcess('ping google.com');
  print('Process started with ID: $processId');
  
  // Wait for a few seconds, then stop it
  await Future.delayed(const Duration(seconds: 3));
  
  if (pm.stopProcess(processId)) {
    print('Process $processId was successfully terminated.');
  } else {
    print('Process $processId could not be found or was already stopped.');
  }

  // The exitCodeFuture for this process will also complete
  // after the process has been killed.
  
  pm.dispose();
}

```

### Extending the Functionality (List-to-Stream Pattern)

A user can easily build a streaming wrapper around this library to suit their needs. A common pattern is to create a `StreamController` and feed the output from the `onStdout` and `onStderr` callbacks into it.

```
// User's custom wrapper class
import 'dart:async';
import 'pm.dart';

class StreamingProcessWrapper {
  final ProcessManagerService _pm;
  final String _processId;
  final _stdoutController = StreamController<String>();

  StreamingProcessWrapper(this._pm, this._processId) {
    _pm.startProcess(
      'some_command',
      onStdout: (data) => _stdoutController.add(data),
      onStderr: (data) => _stdoutController.addError(data),
    );
  }

  Stream<String> get stdoutStream => _stdoutController.stream;
}

```

By providing a simple callback and list-based API, the library remains lightweight and easy to integrate, while still enabling more complex use cases for those who need them.