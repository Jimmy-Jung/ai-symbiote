/**
 * Messenger Bridge 어댑터 인터페이스
 * @author JunyoungJung
 * @date 2026-04-02
 *
 * 새 플랫폼 추가 시 이 인터페이스만 구현하면 됨.
 */

// ── 플랫폼 설정 ──

export type Platform = 'slack' | 'discord' | 'telegram';

export interface PlatformConfig {
  platform: Platform;
  token: string;
  channelId: string;
  /** Slack: signing secret */
  signingSecret?: string;
  /** Slack: app-level token (Socket Mode) */
  appToken?: string;
  /** 허용된 사용자 ID 목록 (비어있으면 모든 사용자 허용) */
  allowedUserIds?: string[];
}

// ── 메시지 타입 ──

export type NotificationLevel = 'info' | 'warn' | 'error' | 'success';

export interface NotificationMessage {
  title: string;
  body: string;
  level: NotificationLevel;
  fields?: Record<string, string>;
  timestamp: string;
}

export interface ApprovalRequest {
  id: string;
  title: string;
  context: string;
  taskDescription: string;
  iteration: number;
  maxIterations: number;
  phase: string;
  options: ApprovalOption[];
  timeoutSeconds: number;
}

export interface ApprovalOption {
  id: string;
  label: string;
  style?: 'primary' | 'danger';
}

// ── 사용자 액션/메시지 ──

export interface UserAction {
  platform: Platform;
  userId: string;
  channelId: string;
  messageId: string;
  actionId: string;
  value?: string;
  requestId: string;
}

export interface UserMessage {
  platform: Platform;
  userId: string;
  channelId: string;
  text: string;
  timestamp: string;
}

export type ActionHandler = (action: UserAction) => Promise<void>;
export type MessageHandler = (message: UserMessage) => Promise<void>;

// ── 어댑터 인터페이스 ──

export interface MessengerAdapter {
  readonly platform: Platform;

  /** 플랫폼 연결 */
  connect(config: PlatformConfig): Promise<void>;

  /** 연결 해제 */
  disconnect(): Promise<void>;

  /** Stage 1: 알림 전송. 반환값은 메시지 ID */
  sendNotification(channelId: string, msg: NotificationMessage): Promise<string>;

  /** Stage 2: 승인 요청 전송 (버튼 포함). 반환값은 메시지 ID */
  sendApprovalRequest(channelId: string, req: ApprovalRequest): Promise<string>;

  /** 기존 메시지 업데이트 (승인 완료 표시 등) */
  updateMessage(channelId: string, msgId: string, msg: NotificationMessage): Promise<void>;

  /** 버튼 클릭 등 액션 핸들러 등록 */
  onAction(handler: ActionHandler): void;

  /** 텍스트 메시지 핸들러 등록 (Stage 3) */
  onMessage(handler: MessageHandler): void;

  /** 연결 상태 확인 */
  isConnected(): boolean;
}
