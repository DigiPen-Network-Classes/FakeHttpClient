/***************************
 *
 * CS 260 Assignment 3 Client (HTTP Test Client) Solution
 * Author: Matthew Picioccio
 * DigiPen Institute of Technology
 * Last Updated: Fall 2024
 * 
 * This program is used as a test client, with appropriate logging behavior,
 * to aid in testing of Assignment 3 proxy projects.
 * 
 * NOTE: This is authored for clarity of reference, not for good engineering practices.
 *
 ***************************/


#include <WinSock2.h>
#include <WS2tcpip.h>
#include <iostream>
#include <chrono>
#include <ctime>
#include <thread>

// constants
unsigned long nonBlockingEnabled = 1; // must not be const for ioctlsocket
const int RECV_BUFFER_LEN = 1500;
const bool IMMEDIATE_MODE = 1;



void PrintCurrentTime()
{
    char timeStr[256];
    auto time = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    ctime_s(timeStr, 256, &time);
    printf("%s\n", timeStr);
}


int main(int argc, char* argv[])
{
    // -- Declarations
    // NOTE: All variables defined initially (C-style) to be compatible with goto
    char url[256];
    char resource[256];
    ZeroMemory(url, 256);
    ZeroMemory(resource, 256);

    unsigned short proxyPort;
    sockaddr_in destinationAddress;
    SOCKET tcpSocket;

    std::string message;
    const char* sendBuffer;
    int sendBufferLength;

    int recvBufferLength = RECV_BUFFER_LEN;
    char* recvBuffer = new char[RECV_BUFFER_LEN];
    char* recvBufferOriginal = recvBuffer;
    ZeroMemory(recvBuffer, RECV_BUFFER_LEN);

    // timekeeping
    std::chrono::steady_clock::time_point start_time, connected_time, end_time;
    long long total_duration, connection_duration;

    // -- Argument Parsing and Validation
    if (argc != 3)
    {
        std::cerr << "Expected usage: CS260_Assignment3_Client.exe <url> <proxy_port>" << std::endl;
        return 1;
    }

    int tokens = sscanf_s(argv[1], "http://%255[^/]%255[^\n]", url, 256, resource, 256);
    if (tokens < 1) 
    {
        std::cerr << "Expected usage: CS260_Assignment3_Client.exe <url> <proxy_port>" << std::endl;
        return 1;
    }
    if (tokens < 2)
    {
        strcpy_s(resource, "/");
    }

    tokens = sscanf_s(argv[2], "%hu", &proxyPort);
    if (tokens < 1) 
    {
        std::cerr << "Expected usage: CS260_Assignment3_Client.exe <url> <proxy_port>" << std::endl;
        return 1;
    }

    // Disable buffering for stdout
    setvbuf(stdout, NULL, _IONBF, 0);

    // -- WSA Startup
    WSADATA wsaData;
    int res = WSAStartup(MAKEWORD(2, 2), &wsaData);
    if (res != 0)
    {
        std::cerr << "Error in WSAStartup: " << WSAGetLastError() << std::endl;
        return 1;
    }

    // -- Destination Address Construction (including DNS resolution)
    memset(&destinationAddress.sin_zero, 0, 8);
    destinationAddress.sin_family = AF_INET;
    destinationAddress.sin_port = htons(proxyPort);
    res = inet_pton(AF_INET, "127.0.0.1", &destinationAddress.sin_addr);
    if (res != 1)
    {
        std::cerr << "Unable to build proxy address with inet_pton. " << WSAGetLastError() << std::endl;
        goto end;
    }

    // -- Socket construction
    tcpSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (tcpSocket == INVALID_SOCKET)
    {
        std::cerr << "Error creating a socket: " << WSAGetLastError() << std::endl;
        goto end;
    }

    // -- Output the current time (start of this client operation)
    printf("Operation Started At: ");
    PrintCurrentTime();

    // start time for calculating differences later:
    start_time = std::chrono::steady_clock::now();

    // -- Connect to remote server
    // NOTE: Per assignment requirements, this did not need to be non-blocking. 
    // It's simpler this way, but non-blocking connect() is also acceptable.
    res = connect(tcpSocket, (const sockaddr*)&destinationAddress, (int)sizeof(destinationAddress));
    if (res == SOCKET_ERROR)
    {
        std::cerr << "Error from connect: " << WSAGetLastError() << std::endl;
        goto end_socket;
    }

    printf("Connected At: ");
    PrintCurrentTime();
    connected_time = std::chrono::steady_clock::now();


    // -- Set the socket as non-blocking
    res = ioctlsocket(tcpSocket, FIONBIO, &nonBlockingEnabled);

    // -- Building the HTTP request
    message = "";
    message += "GET " + std::string(resource) + " HTTP/1.1\r\n";
    message += "Host: " + std::string(url) + "\r\n";
    message += "Connection: close\r\n";
    message += "User-Agent: curl/8.9.1\r\n";
    message += "Accept: */*\r\n";
    message += "\r\n";

    // -- Sending the HTTP request
    sendBuffer = message.c_str();
    sendBufferLength = (int)message.length();
    do
    {
        res = send(tcpSocket, sendBuffer, sendBufferLength, 0);
        if (res == SOCKET_ERROR)
        {
            int lastError = WSAGetLastError();
            if ((lastError != EAGAIN) && (lastError != WSAEWOULDBLOCK))
            {
                std::cerr << "Error from send: " << lastError << std::endl;
                goto end_socket;
            }
        }
        else {
            sendBuffer += res;
            sendBufferLength -= res;
        }
    } while (res != 0);

    shutdown(tcpSocket, SD_SEND);

    printf("Send Complete At ");
    PrintCurrentTime();

    // -- Receive all data
    // NOTE: the server will close the socket on its side, so we don't need to parse the length
    do {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        memset(recvBuffer, 0, recvBufferLength);
        res = recv(tcpSocket, recvBuffer, recvBufferLength - 1, 0);
        if (res == SOCKET_ERROR)
        {
            int lastError = WSAGetLastError();
            // ignore expected errors (Win32)
            if ((lastError != EAGAIN) && (lastError != WSAEWOULDBLOCK))
            {
                std::cerr << "Error from recv: " << lastError << std::endl;
                goto end_socket;
            }
        }
        else 
        {
            if (res > 0) {
                recvBuffer[res] = '\0'; // null terminate the string
                printf("%s", recvBuffer);
            }
        }
    } while (res != 0);
    delete[] recvBufferOriginal;

    // -- Shutdown the socket (for both)
    res = shutdown(tcpSocket, SD_BOTH);
    if (res != 0)
    {
        std::cerr << "Error in shutdown: " << WSAGetLastError() << std::endl;
        goto end_socket;
    }

    // -- Close the socket
end_socket:
    res = closesocket(tcpSocket);
    if (res != 0)
    {
        std::cerr << "Error in closesocket: " << WSAGetLastError() << std::endl;
        goto end;
    }

    // -- Output the current time (end of this client operation)
    printf("Operation Completed At: ");
    PrintCurrentTime();
    end_time = std::chrono::steady_clock::now();
    connection_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - connected_time).count();
    total_duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();
    printf("Connected: %lld ms\n", connection_duration);
    printf("Total Elapsed: %lld ms\n", total_duration);

    // -- Cleanup WSA
end:
    res = WSACleanup();
    if (res != 0)
    {
        std::cerr << "Error in WSACleanup: " << WSAGetLastError() << std::endl;
        return 1;
    }

    return 0;
}