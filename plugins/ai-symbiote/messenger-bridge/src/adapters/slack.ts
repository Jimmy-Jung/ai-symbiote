/**
 * Slack 어댑터 — Bolt (Socket Mode) 기반
 * @author JunyoungJung
 * @date 2026-04-02
 */

import { App } from '@slack/bolt';
import type {
  MessengerAdapter,
  PlatformConfig,
  NotificationMessage,
  ApprovalRequest,
  ActionHandler,
  MessageHandler,
  UserAction,
  UserMessage,
} from './types.js';
import { toPlainText } from '../formatters/messages.ko.js';

const LEVEL_COLOR: Record<string, string> = {
  info: '#2196F3',
  warn: '#FF9800',
  error: '#F44336',
  success: '#4CAF50',
};

export class SlackAdapter implements MessengerAdapter {
  readonly platform = 'slack' as const;
  private app: App | null = null;
  private connected = false;
  private actionHandler: ActionHandler | null = null;
  private messageHandler: MessageHandler | null = null;
  private pendingModify: { requestId: string; userId: string } | null = null;

  async connect(config: PlatformConfig): Promise<void> {
    this.app = new App({
      token: config.token,
      signingSecret: config.signingSecret!,
      socketMode: true,
      appToken: config.appToken!,
    });

    // 버튼 액션 핸들링
    this.app.action(/^(approve|reject|modify):(.+)$/, async ({ action, ack, body }) => {
      await ack();
      if (!this.actionHandler || action.type !== 'button') return;

      const btnAction = action as { action_id: string };
      const [actionId, requestId] = btnAction.action_id.split(':').reverse();
      const realActionId = btnAction.action_id.split(':')[0];

      const userAction: UserAction = {
        platform: 'slack',
        userId: body.user.id,
        channelId: body.channel?.id ?? '',
        messageId: (body as any).message?.ts ?? '',
        actionId: realActionId,
        requestId: requestId ?? '',
      };

      if (realActionId === 'modify') {
        this.pendingModify = { requestId: requestId ?? '', userId: body.user.id };
      } else {
        await this.actionHandler(userAction);
      }
    });

    // 텍스트 메시지 핸들링
    this.app.message(async ({ message, say }) => {
      if (!('text' in message) || message.subtype) return;
      const text = message.text ?? '';

      if (this.pendingModify && message.user === this.pendingModify.userId && this.actionHandler) {
        const action: UserAction = {
          platform: 'slack',
          userId: message.user,
          channelId: message.channel,
          messageId: message.ts,
          actionId: 'modify',
          value: text,
          requestId: this.pendingModify.requestId,
        };
        await this.actionHandler(action);
        this.pendingModify = null;
        await say('수정 지시가 전달되었습니다.');
        return;
      }

      if (this.messageHandler) {
        const msg: UserMessage = {
          platform: 'slack',
          userId: message.user ?? '',
          channelId: message.channel,
          text,
          timestamp: new Date().toISOString(),
        };
        await this.messageHandler(msg);
      }
    });

    await this.app.start();
    this.connected = true;
  }

  async disconnect(): Promise<void> {
    if (this.app) {
      await this.app.stop();
      this.connected = false;
    }
  }

  async sendNotification(channelId: string, msg: NotificationMessage): Promise<string> {
    if (!this.app) throw new Error('App not connected');
    const result = await this.app.client.chat.postMessage({
      channel: channelId,
      text: msg.title ? toPlainText(msg) : msg.body,
      attachments: [{
        color: LEVEL_COLOR[msg.level] ?? LEVEL_COLOR.info,
        fields: msg.fields
          ? Object.entries(msg.fields).map(([k, v]) => ({ title: k, value: v, short: true }))
          : undefined,
      }],
    });
    return result.ts ?? '';
  }

  async sendApprovalRequest(channelId: string, req: ApprovalRequest): Promise<string> {
    if (!this.app) throw new Error('App not connected');

    let text = `⚠️ *${req.title}*\n\n${req.context}`;
    text += `\n• 단계: ${req.phase} | 반복: ${req.iteration}/${req.maxIterations}`;
    if (req.taskDescription) text += `\n• 제안: ${req.taskDescription}`;
    text += `\n⏰ 타임아웃: ${Math.round(req.timeoutSeconds / 60)}분`;

    const buttons = req.options.map(opt => ({
      type: 'button' as const,
      text: { type: 'plain_text' as const, text: opt.label },
      action_id: `${opt.id}:${req.id}`,
      style: opt.style === 'primary' ? 'primary' as const
        : opt.style === 'danger' ? 'danger' as const
        : undefined,
    }));

    const result = await this.app.client.chat.postMessage({
      channel: channelId,
      text,
      blocks: [
        { type: 'section', text: { type: 'mrkdwn', text } },
        { type: 'actions', elements: buttons },
      ],
    });
    return result.ts ?? '';
  }

  async updateMessage(channelId: string, msgId: string, msg: NotificationMessage): Promise<void> {
    if (!this.app) throw new Error('App not connected');
    await this.app.client.chat.update({
      channel: channelId,
      ts: msgId,
      text: msg.title ? toPlainText(msg) : msg.body,
    });
  }

  onAction(handler: ActionHandler): void {
    this.actionHandler = handler;
  }

  onMessage(handler: MessageHandler): void {
    this.messageHandler = handler;
  }

  isConnected(): boolean {
    return this.connected;
  }
}
