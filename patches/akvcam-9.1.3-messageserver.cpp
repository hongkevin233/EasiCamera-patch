/* akvirtualcamera, virtual camera for Mac and Windows.
 * Copyright (C) 2020  Gonzalo Exequiel Pedone
 *
 * akvirtualcamera is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * akvirtualcamera is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with akvirtualcamera. If not, see <http://www.gnu.org/licenses/>.
 *
 * Web-Site: http://webcamoid.github.io/
 */

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <map>
#include <mutex>
#include <thread>
#include <windows.h>
#include <sddl.h>

#include "messageserver.h"
#include "utils.h"
#include "VCamUtils/src/logger.h"

namespace AkVCam
{
    struct PipeThread
    {
        std::shared_ptr<std::thread> thread;
        std::atomic<bool> finished {false};
    };

    using PipeThreadPtr = std::shared_ptr<PipeThread>;

    class MessageServerPrivate
    {
        public:
            MessageServer *self;
            std::string m_pipeName;
            std::map<uint32_t, MessageHandler> m_handlers;
            MessageServer::ServerMode m_mode {MessageServer::ServerModeReceive};
            std::thread m_mainThread;
            std::vector<PipeThreadPtr> m_clientsThreads;
            std::mutex m_mutex;
            std::condition_variable_any m_exitCheckLoop;
            bool m_running {false};

            explicit MessageServerPrivate(MessageServer *self);
            bool startReceive(bool wait=false);
            void stopReceive(bool wait=false);
            void messagesLoop();
            void processPipe(PipeThreadPtr pipeThread, HANDLE pipe);
    };
}

AkVCam::MessageServer::MessageServer()
{
    this->d = new MessageServerPrivate(this);
}

AkVCam::MessageServer::~MessageServer()
{
    this->stop();
    delete this->d;
}

std::string AkVCam::MessageServer::pipeName() const
{
    return this->d->m_pipeName;
}

std::string &AkVCam::MessageServer::pipeName()
{
    return this->d->m_pipeName;
}

void AkVCam::MessageServer::setPipeName(const std::string &pipeName)
{
    this->d->m_pipeName = pipeName;
}

AkVCam::MessageServer::ServerMode AkVCam::MessageServer::mode() const
{
    return this->d->m_mode;
}

AkVCam::MessageServer::ServerMode &AkVCam::MessageServer::mode()
{
    return this->d->m_mode;
}

void AkVCam::MessageServer::setMode(ServerMode mode)
{
    this->d->m_mode = mode;
}

void AkVCam::MessageServer::setHandlers(const std::map<uint32_t, MessageHandler> &handlers)
{
    this->d->m_handlers = handlers;
}

bool AkVCam::MessageServer::start(bool wait)
{
    AkLogFunction();

    switch (this->d->m_mode) {
    case ServerModeReceive:
        AkLogInfo() << "Starting mode receive" << std::endl;

        return this->d->startReceive(wait);

    case ServerModeSend:
        AkLogInfo() << "Starting mode send" << std::endl;
    }

    return false;
}

void AkVCam::MessageServer::stop(bool wait)
{
    AkLogFunction();

    if (this->d->m_mode == ServerModeReceive)
        this->d->stopReceive(wait);
}

BOOL AkVCam::MessageServer::sendMessage(Message *message,
                                        uint32_t timeout)
{
    return this->sendMessage(this->d->m_pipeName, message, timeout);
}

BOOL AkVCam::MessageServer::sendMessage(const Message &messageIn,
                                        Message *messageOut,
                                        uint32_t timeout)
{
    return this->sendMessage(this->d->m_pipeName,
                             messageIn,
                             messageOut,
                             timeout);
}

BOOL AkVCam::MessageServer::sendMessage(const std::string &pipeName,
                                        Message *message,
                                        uint32_t timeout)
{
    return sendMessage(pipeName, *message, message, timeout);
}

    // EASI patch: persistent client pipe handles.
    // CallNamedPipeA creates a new pipe connection per call, and the server
    // side spawns a named pipe instance + a worker thread for EVERY message
    // (one per video frame). That churn leaks ~1 handle/frame and burns CPU.
    // Keep one connection per pipe name and reuse it with TransactNamedPipe.
    namespace {
        std::mutex &clientPipesMutex()
        {
            static std::mutex mutex;

            return mutex;
        }

        std::map<std::string, HANDLE> &clientPipes()
        {
            static std::map<std::string, HANDLE> pipes;

            return pipes;
        }

        void closeClientPipe(const std::string &pipeName)
        {
            auto &pipes = clientPipes();
            auto it = pipes.find(pipeName);

            if (it == pipes.end())
                return;

            if (it->second != INVALID_HANDLE_VALUE)
                CloseHandle(it->second);

            pipes.erase(it);
        }

        HANDLE acquireClientPipe(const std::string &pipeName,
                                 uint32_t timeout)
        {
            auto &pipes = clientPipes();
            auto it = pipes.find(pipeName);

            if (it != pipes.end())
                return it->second;

            DWORD waitMs = timeout == 0? 1000: (std::min)(DWORD(timeout), DWORD(1000));

            for (int i = 0; i < 5; i++) {
                HANDLE pipe = CreateFileA(pipeName.c_str(),
                                          GENERIC_READ | GENERIC_WRITE,
                                          0,
                                          nullptr,
                                          OPEN_EXISTING,
                                          0,
                                          nullptr);

                if (pipe != INVALID_HANDLE_VALUE) {
                    DWORD mode = PIPE_READMODE_MESSAGE;
                    SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr);
                    pipes[pipeName] = pipe;

                    return pipe;
                }

                auto lastError = GetLastError();

                if (lastError == ERROR_PIPE_BUSY) {
                    WaitNamedPipeA(pipeName.c_str(), waitMs);

                    continue;
                }

                std::this_thread::sleep_for(std::chrono::milliseconds(200));
            }

            return INVALID_HANDLE_VALUE;
        }
    }

BOOL AkVCam::MessageServer::sendMessage(const std::string &pipeName,
                                        const Message &messageIn,
                                        Message *messageOut,
                                        uint32_t timeout)
{
    AkLogFunction();
    AkLogDebug() << "Pipe: " << pipeName << std::endl;
    AkLogDebug() << "Message ID: " << stringFromMessageId(messageIn.messageId) << std::endl;

    std::lock_guard<std::mutex> lock(clientPipesMutex());

    for (int i = 0; i < 5; i++) {
        auto pipe = acquireClientPipe(pipeName, timeout);

        if (pipe == INVALID_HANDLE_VALUE)
            break;

        Message reply;
        DWORD bytesTransferred = 0;
        auto result = TransactNamedPipe(pipe,
                                        const_cast<Message *>(&messageIn),
                                        DWORD(sizeof(Message)),
                                        &reply,
                                        DWORD(sizeof(Message)),
                                        &bytesTransferred,
                                        nullptr);

        if (result && bytesTransferred == sizeof(Message)) {
            if (messageOut)
                *messageOut = reply;

            return TRUE;
        }

        // Broken or desynchronized connection: drop it and reconnect.
        closeClientPipe(pipeName);
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }

    AkLogError() << "Error sending message" << std::endl;
    auto lastError = GetLastError();

    if (lastError)
        AkLogError() << stringFromError(lastError) << std::endl;

    return FALSE;
}

AkVCam::MessageServerPrivate::MessageServerPrivate(MessageServer *self):
    self(self)
{
}

bool AkVCam::MessageServerPrivate::startReceive(bool wait)
{
    AkLogFunction();
    AkLogDebug() << "Wait: " << wait << std::endl;
    AKVCAM_EMIT(this->self, StateChanged, MessageServer::StateAboutToStart)
    this->m_running = true;

    if (wait) {
        AKVCAM_EMIT(this->self, StateChanged, MessageServer::StateStarted)
        AkLogDebug() << "Server ready." << std::endl;
        this->messagesLoop();
    } else {
        this->m_mainThread = std::thread(&MessageServerPrivate::messagesLoop, this);
        AKVCAM_EMIT(this->self, StateChanged, MessageServer::StateStarted)
        AkLogDebug() << "Server ready." << std::endl;
    }

    return true;
}

void AkVCam::MessageServerPrivate::stopReceive(bool wait)
{
    AkLogFunction();

    if (!this->m_running)
        return;

    AkLogDebug() << "Stopping clients threads." << std::endl;
    AKVCAM_EMIT(this->self, StateChanged, MessageServer::StateAboutToStop)
    this->m_running = false;

    // wake up current pipe thread.
    Message message;
    message.messageId = AKVCAM_ASSISTANT_MSG_ISALIVE;
    message.dataSize = sizeof(MsgIsAlive);
    MessageServer::sendMessage(this->m_pipeName, &message);

    if (!wait)
        this->m_mainThread.join();
}

void AkVCam::MessageServerPrivate::messagesLoop()
{
    AkLogFunction();
    AkLogDebug() << "Initializing security descriptor." << std::endl;

    // Define who can read and write from pipe.

    /* Define the SDDL for the DACL.
     *
     * https://msdn.microsoft.com/en-us/library/windows/desktop/aa379570(v=vs.85).aspx
     */
    static const TCHAR descriptor[] =
            TEXT("D:")                   // Discretionary ACL
            TEXT("(D;OICI;GA;;;BG)")     // Deny access to Built-in Guests
            TEXT("(D;OICI;GA;;;AN)")     // Deny access to Anonymous Logon
            TEXT("(A;OICI;GRGWGX;;;AU)") // Allow read/write/execute to Authenticated Users
            TEXT("(A;OICI;GA;;;BA)");    // Allow full control to Administrators

    SECURITY_ATTRIBUTES securityAttributes;
    PSECURITY_DESCRIPTOR securityDescriptor =
            LocalAlloc(LPTR, SECURITY_DESCRIPTOR_MIN_LENGTH);

    if (!securityDescriptor) {
        AkLogError() << "Security descriptor not allocated" << std::endl;

        return;
    }

    if (!InitializeSecurityDescriptor(securityDescriptor,
                                      SECURITY_DESCRIPTOR_REVISION)) {
        LocalFree(securityDescriptor);
        AkLogError() << "Can't initialize security descriptor: "
                     << stringFromError(GetLastError())
                     << " (" << GetLastError() << ")"
                     << std::endl;

        return;
    }

    AkLogDebug() << "Getting security descriptor from string." << std::endl;

    if (!ConvertStringSecurityDescriptorToSecurityDescriptor(descriptor,
                                                             SDDL_REVISION_1,
                                                             &securityDescriptor,
                                                             nullptr)) {
        LocalFree(securityDescriptor);
        AkLogError() << "Can't read security descriptor from string: "
                     << stringFromError(GetLastError())
                     << " (" << GetLastError() << ")"
                     << std::endl;

        return;
    }

    securityAttributes.nLength = sizeof(SECURITY_ATTRIBUTES);
    securityAttributes.lpSecurityDescriptor = securityDescriptor;
    securityAttributes.bInheritHandle = TRUE;
    AkLogDebug() << "Pipe name: " << this->m_pipeName << std::endl;

    while (this->m_running) {
        // Clean death threads.
        for (;;) {
            auto it = std::find_if(this->m_clientsThreads.begin(),
                                   this->m_clientsThreads.end(),
                                   [] (const PipeThreadPtr &thread) -> bool {
                return thread->finished;
            });

            if (it == this->m_clientsThreads.end())
                break;

            (*it)->thread->join();
            this->m_clientsThreads.erase(it);
        }

        AkLogDebug() << "Creating pipe." << std::endl;
        auto pipe = CreateNamedPipeA(this->m_pipeName.c_str(),
                                     PIPE_ACCESS_DUPLEX,
                                     PIPE_TYPE_MESSAGE
                                     | PIPE_READMODE_MESSAGE
                                     | PIPE_WAIT,
                                     PIPE_UNLIMITED_INSTANCES,
                                     sizeof(Message),
                                     sizeof(Message),
                                     0,
                                     &securityAttributes);

        if (pipe == INVALID_HANDLE_VALUE)
            continue;

        AkLogDebug() << "Connecting pipe." << std::endl;
        auto connected = ConnectNamedPipe(pipe, nullptr);

        if (connected || GetLastError() == ERROR_PIPE_CONNECTED) {
            auto thread = std::make_shared<PipeThread>();
            thread->thread =
                    std::make_shared<std::thread>(&MessageServerPrivate::processPipe,
                                                  this,
                                                  thread,
                                                  pipe);
            this->m_clientsThreads.push_back(thread);
        } else {
            AkLogError() << "Failed connecting pipe." << std::endl;
            CloseHandle(pipe);
        }
    }

    for (auto &thread: this->m_clientsThreads)
        thread->thread->join();

    LocalFree(securityDescriptor);
    AKVCAM_EMIT(this->self, StateChanged, MessageServer::StateStopped)
    AkLogDebug() << "Server stopped." << std::endl;
}

void AkVCam::MessageServerPrivate::processPipe(PipeThreadPtr pipeThread,
                                               HANDLE pipe)
{
    for (;;) {
        AkLogDebug() << "Reading message." << std::endl;

        Message message;
        DWORD bytesTransferred = 0;
        auto result = ReadFile(pipe,
                               &message,
                               DWORD(sizeof(Message)),
                               &bytesTransferred,
                               nullptr);

        if (!result || bytesTransferred == 0) {
            AkLogError() << "Failed reading from pipe." << std::endl;
            auto lastError = GetLastError();

            if (lastError)
                AkLogError() << stringFromError(lastError) << std::endl;

            break;
        }

        AkLogDebug() << "Message ID: " << stringFromMessageId(message.messageId) << std::endl;

        if (this->m_handlers.count(message.messageId))
            this->m_handlers[message.messageId](&message);

        AkLogDebug() << "Writing message." << std::endl;
        result = WriteFile(pipe,
                           &message,
                           DWORD(sizeof(Message)),
                           &bytesTransferred,
                           nullptr);

        if (!result || bytesTransferred != DWORD(sizeof(Message))) {
            AkLogError() << "Failed writing to pipe." << std::endl;
            auto lastError = GetLastError();

            if (lastError)
                AkLogError() << stringFromError(lastError) << std::endl;

            break;
        }
    }

    AkLogDebug() << "Closing pipe." << std::endl;
    FlushFileBuffers(pipe);
    DisconnectNamedPipe(pipe);
    CloseHandle(pipe);
    pipeThread->finished = true;
    AkLogDebug() << "Pipe thread finished." << std::endl;
}
