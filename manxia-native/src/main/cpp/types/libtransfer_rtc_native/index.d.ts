/**
 * Transfer RTC Native Module TypeScript Definitions
 */

export interface TransferRtcNativeCapabilities {
  nativeModuleLoaded: boolean;
  backend: string;
  backendVersion: string;
  apiVersion: string;
  dataChannelSupported: boolean;
  message: string;
}

export interface TransferRtcNativeResult {
  success: boolean;
  peerId: string;
  operation: string;
  message: string;
  errorCode: string;
  backend: string;
}

export interface TransferRtcNativeSdpResult {
  success: boolean;
  peerId: string;
  sdpType: string;
  sdp: string;
  message: string;
  errorCode: string;
  backend: string;
}

export interface TransferRtcNativeEvent {
  type: string;
  peerId: string;
  payload: string;
  sdpType: string;
  sdp: string;
  candidate: string;
  sdpMid: string;
  sdpMLineIndex: number;
  message: string;
  state: string;
  timestamp: number;
}

export interface TransferRtcNativeEventList {
  success: boolean;
  peerId: string;
  message: string;
  errorCode: string;
  backend: string;
  events: TransferRtcNativeEvent[];
}

export function getCapabilities(): TransferRtcNativeCapabilities;
export function createPeer(sessionId: string, role: string): TransferRtcNativeResult;
export function closePeer(peerId: string): TransferRtcNativeResult;
export function createOffer(peerId: string): TransferRtcNativeSdpResult;
export function createAnswer(peerId: string): TransferRtcNativeSdpResult;
export function setRemoteDescription(peerId: string, type: string, sdp: string): TransferRtcNativeResult;
export function addIceCandidate(
  peerId: string,
  candidate: string,
  sdpMid: string,
  sdpMLineIndex: number
): TransferRtcNativeResult;
export function sendText(peerId: string, text: string): TransferRtcNativeResult;
export function pollEvents(peerId: string): TransferRtcNativeEventList;
