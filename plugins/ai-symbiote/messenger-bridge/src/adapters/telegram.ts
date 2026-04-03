/**
 * Telegram 어댑터 — telegraf 기반
 * @author JunyoungJung
 * @date 2026-04-02
 */

import { Telegraf, Markup } from 'telegraf';
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

export class TelegramAdapter implements MessengerAdapter {
  readonly platform = 'telegram' as const;
  private bot: Telegraf | null = null;
  private connected = false;
  private actionHandler: ActionHandler | null = null;
  private messageHandler: MessageHandler | null = null;

  async connect(config: PlatformConfig): Promise<void> {
    this.bot = new Telegraf(config.token);

    // 버튼 콜백 핸들링
    this.bot.on('callback_query', async (ctx) => {
      if (!this.actionHandler) return;
      const data = 'data' in ctx.callbackQuery ? ctx.callbackQuery.data : undefined;
      if (!data) return;

      // 데이터 형식: requestId:actionId
      const [requestId, actionId] = data.split(':');
      if (!requestId || !actionId) return;

      const action: UserAction = {
        platform: 'telegram',
        userId: String(ctx.from.id),
        channelId: String(ctx.chat?.id ?? ''),
        messageId: String(ctx.callbackQuery.message?.message_id ?? ''),
        actionId,
        requestId,
      };

      // modify인 경우 코멘트 요청
      if (actionId === 'modify') {
        await ctx.reply('수정 지시를 입력하세요:');
        // 다음 텍스트 메시지를 modify의 코멘트로 처리하기 위해 임시 상태 저장
        (this.bot as any).__pendingModify = { requestId, userId: String(ctx.from.id) };
      } else {
        await this.actionHandler(action);
        await ctx.answerCbQuery(`${actionId === 'approve' ? '승인' : '거부'}되었습니다.`);
      }
    });

    // 텍스트 메시지 핸들링
    this.bot.on('text', async (ctx) => {
      // pending modify가 있으면 그 응답으로 처리
      const pending = (this.bot as any).__pendingModify;
      if (pending && String(ctx.from.id) === pending.userId && this.actionHandler) {
        const action: UserAction = {
          platform: 'telegram',
          userId: String(ctx.from.id),
          channelId: String(ctx.chat.id),
          messageId: String(ctx.message.message_id),
          actionId: 'modify',
          value: ctx.message.text,
          requestId: pending.requestId,
        };
        await this.actionHandler(action);
        (this.bot as any).__pendingModify = null;
        await ctx.reply('수정 지시가 전달되었습니다.');
        return;
      }

      // 일반 메시지 → Stage 3 세션 제어
      if (this.messageHandler) {
        const msg: UserMessage = {
          platform: 'telegram',
          userId: String(ctx.from.id),
          channelId: String(ctx.chat.id),
          text: ctx.message.text,
          timestamp: new Date().toISOString(),
        };
        await this.messageHandler(msg);
      }
    });

    // launch()는 long-polling 루프를 시작하므로 await하면 영원히 block됨
    this.bot.launch().catch((err) => {
      console.error('[Telegram] launch 오류:', err);
      this.connected = false;
    });
    this.connected = true;
  }

  async disconnect(): Promise<void> {
    if (this.bot) {
      this.bot.stop('SIGTERM');
      this.connected = false;
    }
  }

  async sendNotification(channelId: string, msg: NotificationMessage): Promise<string> {
    if (!this.bot) throw new Error('Bot not connected');
    const text = msg.title ? toPlainText(msg) : msg.body;
    const sent = await this.bot.telegram.sendMessage(channelId, text, { parse_mode: 'Markdown' });
    return String(sent.message_id);
  }

  async sendApprovalRequest(channelId: string, req: ApprovalRequest): Promise<string> {
    if (!this.bot) throw new Error('Bot not connected');

    let text = `⚠️ *${req.title}*\n\n`;
    text += `${req.context}\n\n`;
    text += `• 단계: ${req.phase}\n`;
    text += `• 반복: ${req.iteration}/${req.maxIterations}\n`;
    if (req.taskDescription) text += `• 제안: ${req.taskDescription}\n`;
    text += `\n⏰ 타임아웃: ${Math.round(req.timeoutSeconds / 60)}분`;

    const buttons = req.options.map(opt =>
      Markup.button.callback(opt.label, `${req.id}:${opt.id}`),
    );

    const sent = await this.bot.telegram.sendMessage(
      channelId,
      text,
      {
        parse_mode: 'Markdown',
        ...Markup.inlineKeyboard(buttons),
      },
    );
    return String(sent.message_id);
  }

  async updateMessage(channelId: string, msgId: string, msg: NotificationMessage): Promise<void> {
    if (!this.bot) throw new Error('Bot not connected');
    const text = msg.title ? toPlainText(msg) : msg.body;
    await this.bot.telegram.editMessageText(channelId, Number(msgId), undefined, text, {
      parse_mode: 'Markdown',
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
