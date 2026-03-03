# PortsMonitor

A macOS application for monitoring network ports and managing processes.

## Features

- **Port Monitoring**: View all active network ports and their associated processes
- **Process Management**: Kill processes that are using specific ports
- **Real-time Monitoring**: Auto-refresh port data at specified intervals
- **Search Functionality**: Filter ports by port number, process name, PID, or protocol
- **User-Friendly Interface**: Clean and intuitive macOS native UI

## Usage

1. **Launch the application**
2. **View port information**: The main window displays all active ports, their protocols, associated processes, and PIDs
3. **Search ports**: Use the search field to filter ports by any criteria
4. **Kill processes**: Select a port in the table and click the "Kill" button to terminate the associated process
5. **Monitor ports**: Toggle the "Monitor" switch to enable automatic refreshing every 5 seconds

## Building and Running

### Prerequisites
- Xcode 14.0 or later
- macOS 13.0 or later

### Build Instructions
1. Clone the repository
2. Open `PortsMonitor.xcodeproj` in Xcode
3. Build and run the application using Xcode

### Alternative Build Method
You can also use the provided build script:

```bash
./build_and_run.sh
```

## How It Works

The application uses macOS system APIs to:
1. List all running processes
2. Identify network sockets for each process
3. Extract port information from socket descriptors
4. Display the information in a sortable, searchable table
5. Provide options to terminate processes

## Safety Note

When killing processes, the application will display a confirmation dialog to prevent accidental termination of important system processes.

## License

MIT License