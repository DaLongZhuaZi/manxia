/**
 * Native RTC 数据通道模块。
 *
 * 有 libdatachannel 预编译库时启用真实 WebRTC PeerConnection/DataChannel 后端；
 * 缺少预编译库时保留稳定 NAPI 外壳并返回 stub 能力。
 */

#include <napi/native_api.h>
#include <hilog/log.h>

#include <atomic>
#include <chrono>
#include <deque>
#include <exception>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#if HAVE_LIBDATACHANNEL
#include <rtc/rtc.hpp>
#include <rtc/version.h>
#endif

#ifndef LOG_DOMAIN
#define LOG_DOMAIN 0x3204
#endif

#ifndef LOG_TAG
#define LOG_TAG "TransferRtcNative"
#endif

#define RTC_LOGI(...) OH_LOG_INFO(LOG_APP, __VA_ARGS__)
#define RTC_LOGW(...) OH_LOG_WARN(LOG_APP, __VA_ARGS__)
#define RTC_LOGE(...) OH_LOG_ERROR(LOG_APP, __VA_ARGS__)

namespace {

#if HAVE_LIBDATACHANNEL
constexpr const char* BACKEND_NAME = "libdatachannel";
constexpr const char* BACKEND_VERSION = RTC_VERSION;
constexpr bool DATA_CHANNEL_SUPPORTED = true;
constexpr const char* CAPABILITY_MESSAGE = "Native RTC DataChannel 后端已接入 libdatachannel。";
#else
constexpr const char* BACKEND_NAME = "stub";
constexpr const char* BACKEND_VERSION = "0.0.0-stub";
constexpr bool DATA_CHANNEL_SUPPORTED = false;
constexpr const char* CAPABILITY_MESSAGE =
    "Native RTC NAPI 外壳已接入，真实 DataChannel 后端尚未接入 libdatachannel。";
#endif

constexpr const char* API_VERSION = "mx-transfer-rtc-native/0.2";
constexpr const char* UNSUPPORTED_CODE = "BACKEND_UNAVAILABLE";
constexpr const char* DATA_CHANNEL_LABEL = "mx-transfer-file/0.1";

struct OperationResult {
    bool success = false;
    std::string peerId;
    std::string operation;
    std::string message;
    std::string errorCode;
    std::string backend = BACKEND_NAME;
};

struct SdpResult {
    bool success = false;
    std::string peerId;
    std::string sdpType;
    std::string sdp;
    std::string message;
    std::string errorCode;
    std::string backend = BACKEND_NAME;
};

struct NativeRtcEvent {
    std::string type;
    std::string peerId;
    std::string payload;
    std::string sdpType;
    std::string sdp;
    std::string candidate;
    std::string sdpMid;
    int32_t sdpMLineIndex = 0;
    std::string message;
    std::string state;
    int64_t timestamp = 0;
};

int64_t NowMs()
{
    const auto now = std::chrono::system_clock::now();
    const auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch());
    return millis.count();
}

napi_value CreateString(napi_env env, const std::string& value)
{
    napi_value result;
    napi_create_string_utf8(env, value.c_str(), value.length(), &result);
    return result;
}

napi_value CreateBool(napi_env env, bool value)
{
    napi_value result;
    napi_get_boolean(env, value, &result);
    return result;
}

napi_value CreateInt32(napi_env env, int32_t value)
{
    napi_value result;
    napi_create_int32(env, value, &result);
    return result;
}

napi_value CreateInt64(napi_env env, int64_t value)
{
    napi_value result;
    napi_create_int64(env, value, &result);
    return result;
}

void SetString(napi_env env, napi_value object, const char* name, const std::string& value)
{
    napi_set_named_property(env, object, name, CreateString(env, value));
}

void SetBool(napi_env env, napi_value object, const char* name, bool value)
{
    napi_set_named_property(env, object, name, CreateBool(env, value));
}

void SetInt32(napi_env env, napi_value object, const char* name, int32_t value)
{
    napi_set_named_property(env, object, name, CreateInt32(env, value));
}

void SetInt64(napi_env env, napi_value object, const char* name, int64_t value)
{
    napi_set_named_property(env, object, name, CreateInt64(env, value));
}

std::string GetStringArgument(napi_env env, napi_value value)
{
    napi_valuetype valueType;
    napi_typeof(env, value, &valueType);
    if (valueType != napi_string) {
        return "";
    }

    size_t length = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &length);
    if (length <= 0) {
        return "";
    }
    std::string buffer(length + 1, '\0');
    napi_get_value_string_utf8(env, value, buffer.data(), buffer.length(), &length);
    return std::string(buffer.c_str(), length);
}

int32_t GetInt32Argument(napi_env env, napi_value value)
{
    napi_valuetype valueType;
    napi_typeof(env, value, &valueType);
    if (valueType != napi_number) {
        return 0;
    }
    int32_t result = 0;
    napi_get_value_int32(env, value, &result);
    return result;
}

napi_value CreateOperationResult(napi_env env, const OperationResult& result)
{
    napi_value object;
    napi_create_object(env, &object);
    SetBool(env, object, "success", result.success);
    SetString(env, object, "peerId", result.peerId);
    SetString(env, object, "operation", result.operation);
    SetString(env, object, "message", result.message);
    SetString(env, object, "errorCode", result.errorCode);
    SetString(env, object, "backend", result.backend);
    return object;
}

napi_value CreateSdpResultValue(napi_env env, const SdpResult& result)
{
    napi_value object;
    napi_create_object(env, &object);
    SetBool(env, object, "success", result.success);
    SetString(env, object, "peerId", result.peerId);
    SetString(env, object, "sdpType", result.sdpType);
    SetString(env, object, "sdp", result.sdp);
    SetString(env, object, "message", result.message);
    SetString(env, object, "errorCode", result.errorCode);
    SetString(env, object, "backend", result.backend);
    return object;
}

OperationResult BuildFailure(const std::string& peerId, const std::string& operation, const std::string& message,
    const std::string& errorCode)
{
    OperationResult result;
    result.success = false;
    result.peerId = peerId;
    result.operation = operation;
    result.message = message;
    result.errorCode = errorCode;
    result.backend = BACKEND_NAME;
    return result;
}

OperationResult BuildSuccess(const std::string& peerId, const std::string& operation, const std::string& message)
{
    OperationResult result;
    result.success = true;
    result.peerId = peerId;
    result.operation = operation;
    result.message = message;
    result.errorCode = "";
    result.backend = BACKEND_NAME;
    return result;
}

SdpResult BuildSdpFailure(const std::string& peerId, const std::string& sdpType, const std::string& message,
    const std::string& errorCode)
{
    SdpResult result;
    result.success = false;
    result.peerId = peerId;
    result.sdpType = sdpType;
    result.sdp = "";
    result.message = message;
    result.errorCode = errorCode;
    result.backend = BACKEND_NAME;
    return result;
}

napi_value CreateNativeRtcEventValue(napi_env env, const NativeRtcEvent& event)
{
    napi_value object;
    napi_create_object(env, &object);
    SetString(env, object, "type", event.type);
    SetString(env, object, "peerId", event.peerId);
    SetString(env, object, "payload", event.payload);
    SetString(env, object, "sdpType", event.sdpType);
    SetString(env, object, "sdp", event.sdp);
    SetString(env, object, "candidate", event.candidate);
    SetString(env, object, "sdpMid", event.sdpMid);
    SetInt32(env, object, "sdpMLineIndex", event.sdpMLineIndex);
    SetString(env, object, "message", event.message);
    SetString(env, object, "state", event.state);
    SetInt64(env, object, "timestamp", event.timestamp);
    return object;
}

std::string ExceptionMessage(const std::exception& error)
{
    return error.what() == nullptr ? "native exception" : error.what();
}

#if HAVE_LIBDATACHANNEL

struct PeerContext {
    std::string peerId;
    std::string sessionId;
    std::string role;
    std::shared_ptr<rtc::PeerConnection> peerConnection;
    std::shared_ptr<rtc::DataChannel> dataChannel;
    std::deque<NativeRtcEvent> events;
    std::mutex mutex;
};

std::mutex gPeersMutex;
std::map<std::string, std::shared_ptr<PeerContext>> gPeers;
std::atomic<uint64_t> gPeerSequence { 1 };

std::string BuildPeerId()
{
    const uint64_t sequence = gPeerSequence.fetch_add(1);
    std::ostringstream stream;
    stream << "native_peer_" << NowMs() << "_" << sequence;
    return stream.str();
}

void PushEvent(const std::shared_ptr<PeerContext>& context, NativeRtcEvent event)
{
    if (context == nullptr) {
        return;
    }
    event.peerId = context->peerId;
    event.timestamp = NowMs();
    std::lock_guard<std::mutex> lock(context->mutex);
    context->events.push_back(std::move(event));
}

std::string PeerStateToString(rtc::PeerConnection::State state)
{
    switch (state) {
        case rtc::PeerConnection::State::New:
            return "new";
        case rtc::PeerConnection::State::Connecting:
            return "connecting";
        case rtc::PeerConnection::State::Connected:
            return "connected";
        case rtc::PeerConnection::State::Disconnected:
            return "disconnected";
        case rtc::PeerConnection::State::Failed:
            return "failed";
        case rtc::PeerConnection::State::Closed:
            return "closed";
        default:
            return "unknown";
    }
}

std::string IceStateToString(rtc::PeerConnection::IceState state)
{
    switch (state) {
        case rtc::PeerConnection::IceState::New:
            return "new";
        case rtc::PeerConnection::IceState::Checking:
            return "checking";
        case rtc::PeerConnection::IceState::Connected:
            return "connected";
        case rtc::PeerConnection::IceState::Completed:
            return "completed";
        case rtc::PeerConnection::IceState::Failed:
            return "failed";
        case rtc::PeerConnection::IceState::Disconnected:
            return "disconnected";
        case rtc::PeerConnection::IceState::Closed:
            return "closed";
        default:
            return "unknown";
    }
}

std::string GatheringStateToString(rtc::PeerConnection::GatheringState state)
{
    switch (state) {
        case rtc::PeerConnection::GatheringState::New:
            return "new";
        case rtc::PeerConnection::GatheringState::InProgress:
            return "in_progress";
        case rtc::PeerConnection::GatheringState::Complete:
            return "complete";
        default:
            return "unknown";
    }
}

std::shared_ptr<PeerContext> FindPeer(const std::string& peerId)
{
    std::lock_guard<std::mutex> lock(gPeersMutex);
    const auto iterator = gPeers.find(peerId);
    if (iterator == gPeers.end()) {
        return nullptr;
    }
    return iterator->second;
}

void AttachDataChannelCallbacks(const std::shared_ptr<PeerContext>& context,
    const std::shared_ptr<rtc::DataChannel>& channel)
{
    if (context == nullptr || channel == nullptr) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(context->mutex);
        context->dataChannel = channel;
    }

    channel->onOpen([context]() {
        NativeRtcEvent event;
        event.type = "data_channel_open";
        event.message = "DataChannel 已打开。";
        event.state = "open";
        PushEvent(context, event);
    });

    channel->onClosed([context]() {
        NativeRtcEvent event;
        event.type = "data_channel_closed";
        event.message = "DataChannel 已关闭。";
        event.state = "closed";
        PushEvent(context, event);
    });

    channel->onError([context](rtc::string error) {
        NativeRtcEvent event;
        event.type = "data_channel_error";
        event.message = error;
        event.state = "error";
        PushEvent(context, event);
    });

    channel->onMessage([context](rtc::message_variant data) {
        NativeRtcEvent event;
        if (std::holds_alternative<rtc::string>(data)) {
            event.type = "message";
            event.message = std::get<rtc::string>(data);
        } else {
            const rtc::binary& binary = std::get<rtc::binary>(data);
            event.type = "binary_message";
            event.message = "收到二进制 DataChannel 消息。";
            event.payload = std::to_string(binary.size());
        }
        PushEvent(context, event);
    });
}

rtc::Description::Type SdpTypeFromString(const std::string& type)
{
    if (type == "offer") {
        return rtc::Description::Type::Offer;
    }
    if (type == "answer") {
        return rtc::Description::Type::Answer;
    }
    if (type == "pranswer") {
        return rtc::Description::Type::Pranswer;
    }
    if (type == "rollback") {
        return rtc::Description::Type::Rollback;
    }
    return rtc::Description::Type::Unspec;
}

void ConfigurePeerCallbacks(const std::shared_ptr<PeerContext>& context)
{
    std::weak_ptr<PeerContext> weakContext = context;
    std::shared_ptr<rtc::PeerConnection> peerConnection = context->peerConnection;

    peerConnection->onLocalDescription([weakContext](rtc::Description description) {
        std::shared_ptr<PeerContext> lockedContext = weakContext.lock();
        if (lockedContext == nullptr) {
            return;
        }
        NativeRtcEvent event;
        event.type = "local_description";
        event.sdpType = description.typeString();
        event.sdp = static_cast<std::string>(description);
        event.payload = event.sdp;
        event.message = "本地 SDP 已生成。";
        PushEvent(lockedContext, event);
    });

    peerConnection->onLocalCandidate([weakContext](rtc::Candidate candidate) {
        std::shared_ptr<PeerContext> lockedContext = weakContext.lock();
        if (lockedContext == nullptr) {
            return;
        }
        NativeRtcEvent event;
        event.type = "local_candidate";
        event.candidate = candidate.candidate();
        event.sdpMid = candidate.mid();
        event.sdpMLineIndex = 0;
        event.payload = event.candidate;
        event.message = "本地 ICE Candidate 已生成。";
        PushEvent(lockedContext, event);
    });

    peerConnection->onStateChange([weakContext](rtc::PeerConnection::State state) {
        std::shared_ptr<PeerContext> lockedContext = weakContext.lock();
        if (lockedContext == nullptr) {
            return;
        }
        NativeRtcEvent event;
        event.type = "peer_state";
        event.state = PeerStateToString(state);
        event.message = "PeerConnection 状态已变化。";
        PushEvent(lockedContext, event);
    });

    peerConnection->onIceStateChange([weakContext](rtc::PeerConnection::IceState state) {
        std::shared_ptr<PeerContext> lockedContext = weakContext.lock();
        if (lockedContext == nullptr) {
            return;
        }
        NativeRtcEvent event;
        event.type = "ice_state";
        event.state = IceStateToString(state);
        event.message = "ICE 状态已变化。";
        PushEvent(lockedContext, event);
    });

    peerConnection->onGatheringStateChange([weakContext](rtc::PeerConnection::GatheringState state) {
        std::shared_ptr<PeerContext> lockedContext = weakContext.lock();
        if (lockedContext == nullptr) {
            return;
        }
        NativeRtcEvent event;
        event.type = "gathering_state";
        event.state = GatheringStateToString(state);
        event.message = "ICE Gathering 状态已变化。";
        PushEvent(lockedContext, event);
    });

    peerConnection->onDataChannel([weakContext](std::shared_ptr<rtc::DataChannel> incoming) {
        std::shared_ptr<PeerContext> lockedContext = weakContext.lock();
        if (lockedContext == nullptr) {
            return;
        }
        NativeRtcEvent event;
        event.type = "data_channel_received";
        event.message = "收到远端 DataChannel。";
        PushEvent(lockedContext, event);
        AttachDataChannelCallbacks(lockedContext, incoming);
    });
}

rtc::Configuration BuildRtcConfiguration()
{
    rtc::Configuration configuration;
    configuration.iceServers.emplace_back("stun:stun.l.google.com:19302");
    configuration.maxMessageSize = 16 * 1024 * 1024;
    return configuration;
}

OperationResult CreateNativePeer(const std::string& sessionId, const std::string& role)
{
    try {
        std::shared_ptr<PeerContext> context = std::make_shared<PeerContext>();
        context->peerId = BuildPeerId();
        context->sessionId = sessionId;
        context->role = role;
        context->peerConnection = std::make_shared<rtc::PeerConnection>(BuildRtcConfiguration());
        ConfigurePeerCallbacks(context);

        if (role != "peer") {
            std::shared_ptr<rtc::DataChannel> channel = context->peerConnection->createDataChannel(DATA_CHANNEL_LABEL);
            AttachDataChannelCallbacks(context, channel);
        }

        {
            std::lock_guard<std::mutex> lock(gPeersMutex);
            gPeers[context->peerId] = context;
        }

        RTC_LOGI("created native peer, peerId=%{public}s, role=%{public}s", context->peerId.c_str(), role.c_str());
        return BuildSuccess(context->peerId, "createPeer", "Native Peer 已创建。");
    } catch (const std::exception& error) {
        return BuildFailure("", "createPeer", ExceptionMessage(error), "CREATE_PEER_FAILED");
    }
}

#endif

napi_value GetCapabilities(napi_env env, napi_callback_info info)
{
    (void)info;
    RTC_LOGI("getCapabilities called, backend=%{public}s", BACKEND_NAME);
    napi_value object;
    napi_create_object(env, &object);
    SetBool(env, object, "nativeModuleLoaded", true);
    SetString(env, object, "backend", BACKEND_NAME);
    SetString(env, object, "backendVersion", BACKEND_VERSION);
    SetString(env, object, "apiVersion", API_VERSION);
    SetBool(env, object, "dataChannelSupported", DATA_CHANNEL_SUPPORTED);
    SetString(env, object, "message", CAPABILITY_MESSAGE);
    return object;
}

napi_value CreatePeer(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string sessionId = argc > 0 ? GetStringArgument(env, args[0]) : "";
    std::string role = argc > 1 ? GetStringArgument(env, args[1]) : "";
#if HAVE_LIBDATACHANNEL
    return CreateOperationResult(env, CreateNativePeer(sessionId, role));
#else
    RTC_LOGW("createPeer called in stub backend, sessionId length=%{public}zu, role=%{public}s",
        sessionId.length(), role.c_str());
    return CreateOperationResult(env, BuildFailure("", "createPeer", CAPABILITY_MESSAGE, UNSUPPORTED_CODE));
#endif
}

napi_value ClosePeer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string peerId = argc > 0 ? GetStringArgument(env, args[0]) : "";
#if HAVE_LIBDATACHANNEL
    std::shared_ptr<PeerContext> context = FindPeer(peerId);
    if (context == nullptr) {
        return CreateOperationResult(env, BuildFailure(peerId, "closePeer", "Native Peer 不存在。", "PEER_NOT_FOUND"));
    }

    {
        std::lock_guard<std::mutex> lock(gPeersMutex);
        gPeers.erase(peerId);
    }

    try {
        std::shared_ptr<rtc::PeerConnection> peerConnection;
        std::shared_ptr<rtc::DataChannel> dataChannel;
        {
            std::lock_guard<std::mutex> lock(context->mutex);
            peerConnection = context->peerConnection;
            dataChannel = context->dataChannel;
        }
        if (dataChannel != nullptr) {
            dataChannel->close();
        }
        if (peerConnection != nullptr) {
            peerConnection->close();
        }
        return CreateOperationResult(env, BuildSuccess(peerId, "closePeer", "Native Peer 已关闭。"));
    } catch (const std::exception& error) {
        return CreateOperationResult(env,
            BuildFailure(peerId, "closePeer", ExceptionMessage(error), "CLOSE_PEER_FAILED"));
    }
#else
    RTC_LOGW("closePeer called in stub backend, peerId=%{public}s", peerId.c_str());
    return CreateOperationResult(env, BuildFailure(peerId, "closePeer", CAPABILITY_MESSAGE, UNSUPPORTED_CODE));
#endif
}

napi_value CreateOffer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string peerId = argc > 0 ? GetStringArgument(env, args[0]) : "";
#if HAVE_LIBDATACHANNEL
    std::shared_ptr<PeerContext> context = FindPeer(peerId);
    if (context == nullptr || context->peerConnection == nullptr) {
        return CreateSdpResultValue(env, BuildSdpFailure(peerId, "offer", "Native Peer 不存在。", "PEER_NOT_FOUND"));
    }

    try {
        context->peerConnection->setLocalDescription(rtc::Description::Type::Offer);
        return CreateSdpResultValue(env, BuildSdpFailure(peerId, "offer",
            "Offer 正在异步生成，请通过 pollEvents 读取 local_description。", "SDP_PENDING"));
    } catch (const std::exception& error) {
        return CreateSdpResultValue(env, BuildSdpFailure(peerId, "offer", ExceptionMessage(error), "CREATE_OFFER_FAILED"));
    }
#else
    RTC_LOGW("createOffer called in stub backend, peerId=%{public}s", peerId.c_str());
    return CreateSdpResultValue(env, BuildSdpFailure(peerId, "offer", CAPABILITY_MESSAGE, UNSUPPORTED_CODE));
#endif
}

napi_value CreateAnswer(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string peerId = argc > 0 ? GetStringArgument(env, args[0]) : "";
#if HAVE_LIBDATACHANNEL
    std::shared_ptr<PeerContext> context = FindPeer(peerId);
    if (context == nullptr || context->peerConnection == nullptr) {
        return CreateSdpResultValue(env, BuildSdpFailure(peerId, "answer", "Native Peer 不存在。", "PEER_NOT_FOUND"));
    }

    try {
        context->peerConnection->setLocalDescription(rtc::Description::Type::Answer);
        return CreateSdpResultValue(env, BuildSdpFailure(peerId, "answer",
            "Answer 正在异步生成，请通过 pollEvents 读取 local_description。", "SDP_PENDING"));
    } catch (const std::exception& error) {
        return CreateSdpResultValue(env, BuildSdpFailure(peerId, "answer", ExceptionMessage(error), "CREATE_ANSWER_FAILED"));
    }
#else
    RTC_LOGW("createAnswer called in stub backend, peerId=%{public}s", peerId.c_str());
    return CreateSdpResultValue(env, BuildSdpFailure(peerId, "answer", CAPABILITY_MESSAGE, UNSUPPORTED_CODE));
#endif
}

napi_value SetRemoteDescription(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string peerId = argc > 0 ? GetStringArgument(env, args[0]) : "";
    std::string sdpType = argc > 1 ? GetStringArgument(env, args[1]) : "";
    std::string sdp = argc > 2 ? GetStringArgument(env, args[2]) : "";
#if HAVE_LIBDATACHANNEL
    std::shared_ptr<PeerContext> context = FindPeer(peerId);
    if (context == nullptr || context->peerConnection == nullptr) {
        return CreateOperationResult(env,
            BuildFailure(peerId, "setRemoteDescription", "Native Peer 不存在。", "PEER_NOT_FOUND"));
    }

    try {
        context->peerConnection->setRemoteDescription(rtc::Description(sdp, SdpTypeFromString(sdpType)));
        return CreateOperationResult(env,
            BuildSuccess(peerId, "setRemoteDescription", "远端 SDP 已设置。"));
    } catch (const std::exception& error) {
        return CreateOperationResult(env,
            BuildFailure(peerId, "setRemoteDescription", ExceptionMessage(error), "SET_REMOTE_DESCRIPTION_FAILED"));
    }
#else
    RTC_LOGW("setRemoteDescription called in stub backend, peerId=%{public}s, type=%{public}s, sdp length=%{public}zu",
        peerId.c_str(), sdpType.c_str(), sdp.length());
    return CreateOperationResult(env, BuildFailure(peerId, "setRemoteDescription", CAPABILITY_MESSAGE, UNSUPPORTED_CODE));
#endif
}

napi_value AddIceCandidate(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string peerId = argc > 0 ? GetStringArgument(env, args[0]) : "";
    std::string candidate = argc > 1 ? GetStringArgument(env, args[1]) : "";
    std::string sdpMid = argc > 2 ? GetStringArgument(env, args[2]) : "";
    int32_t sdpMLineIndex = argc > 3 ? GetInt32Argument(env, args[3]) : 0;
    (void)sdpMLineIndex;
#if HAVE_LIBDATACHANNEL
    std::shared_ptr<PeerContext> context = FindPeer(peerId);
    if (context == nullptr || context->peerConnection == nullptr) {
        return CreateOperationResult(env,
            BuildFailure(peerId, "addIceCandidate", "Native Peer 不存在。", "PEER_NOT_FOUND"));
    }

    try {
        context->peerConnection->addRemoteCandidate(rtc::Candidate(candidate, sdpMid));
        return CreateOperationResult(env, BuildSuccess(peerId, "addIceCandidate", "远端 ICE Candidate 已添加。"));
    } catch (const std::exception& error) {
        return CreateOperationResult(env,
            BuildFailure(peerId, "addIceCandidate", ExceptionMessage(error), "ADD_ICE_CANDIDATE_FAILED"));
    }
#else
    RTC_LOGW("addIceCandidate called in stub backend, peerId=%{public}s, mid=%{public}s, candidate length=%{public}zu",
        peerId.c_str(), sdpMid.c_str(), candidate.length());
    return CreateOperationResult(env, BuildFailure(peerId, "addIceCandidate", CAPABILITY_MESSAGE, UNSUPPORTED_CODE));
#endif
}

napi_value SendText(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string peerId = argc > 0 ? GetStringArgument(env, args[0]) : "";
    std::string text = argc > 1 ? GetStringArgument(env, args[1]) : "";
#if HAVE_LIBDATACHANNEL
    std::shared_ptr<PeerContext> context = FindPeer(peerId);
    if (context == nullptr) {
        return CreateOperationResult(env, BuildFailure(peerId, "sendText", "Native Peer 不存在。", "PEER_NOT_FOUND"));
    }

    std::shared_ptr<rtc::DataChannel> dataChannel;
    {
        std::lock_guard<std::mutex> lock(context->mutex);
        dataChannel = context->dataChannel;
    }

    if (dataChannel == nullptr || !dataChannel->isOpen()) {
        return CreateOperationResult(env,
            BuildFailure(peerId, "sendText", "DataChannel 尚未打开。", "DATA_CHANNEL_NOT_OPEN"));
    }

    try {
        const bool sent = dataChannel->send(text);
        return CreateOperationResult(env,
            BuildSuccess(peerId, "sendText", sent ? "文本消息已发送。" : "文本消息已进入发送缓冲区。"));
    } catch (const std::exception& error) {
        return CreateOperationResult(env, BuildFailure(peerId, "sendText", ExceptionMessage(error), "SEND_TEXT_FAILED"));
    }
#else
    RTC_LOGW("sendText called in stub backend, peerId=%{public}s, text length=%{public}zu", peerId.c_str(), text.length());
    return CreateOperationResult(env, BuildFailure(peerId, "sendText", CAPABILITY_MESSAGE, UNSUPPORTED_CODE));
#endif
}

napi_value PollEvents(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string peerId = argc > 0 ? GetStringArgument(env, args[0]) : "";
    napi_value object;
    napi_create_object(env, &object);
    SetBool(env, object, "success", false);
    SetString(env, object, "peerId", peerId);
    SetString(env, object, "message", CAPABILITY_MESSAGE);
    SetString(env, object, "errorCode", UNSUPPORTED_CODE);
    SetString(env, object, "backend", BACKEND_NAME);

    napi_value eventsArray;
    napi_create_array(env, &eventsArray);

#if HAVE_LIBDATACHANNEL
    std::shared_ptr<PeerContext> context = FindPeer(peerId);
    if (context == nullptr) {
        SetString(env, object, "message", "Native Peer 不存在。");
        SetString(env, object, "errorCode", "PEER_NOT_FOUND");
        napi_set_named_property(env, object, "events", eventsArray);
        return object;
    }

    std::deque<NativeRtcEvent> events;
    {
        std::lock_guard<std::mutex> lock(context->mutex);
        events.swap(context->events);
    }

    uint32_t index = 0;
    for (const NativeRtcEvent& event : events) {
        napi_set_element(env, eventsArray, index, CreateNativeRtcEventValue(env, event));
        index++;
    }

    SetBool(env, object, "success", true);
    SetString(env, object, "message", "Native RTC 事件已读取。");
    SetString(env, object, "errorCode", "");
#endif

    napi_set_named_property(env, object, "events", eventsArray);
    return object;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    RTC_LOGI("Transfer RTC Native module initializing");
    napi_property_descriptor desc[] = {
        { "getCapabilities", nullptr, GetCapabilities, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createPeer", nullptr, CreatePeer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "closePeer", nullptr, ClosePeer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createOffer", nullptr, CreateOffer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createAnswer", nullptr, CreateAnswer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setRemoteDescription", nullptr, SetRemoteDescription, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "addIceCandidate", nullptr, AddIceCandidate, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "sendText", nullptr, SendText, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "pollEvents", nullptr, PollEvents, nullptr, nullptr, nullptr, napi_default, nullptr },
    };

    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    RTC_LOGI("Transfer RTC Native module initialized, backend=%{public}s", BACKEND_NAME);
    return exports;
}
EXTERN_C_END

static napi_module transferRtcModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "transfer_rtc_native",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterTransferRtcModule(void)
{
    napi_module_register(&transferRtcModule);
}
