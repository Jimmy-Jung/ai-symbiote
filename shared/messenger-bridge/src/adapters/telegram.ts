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
  private allowedUserIds: Set<string> = new Set();

  /** 사용자 인증 확인 */
  private isAuthorized(userId: string): boolean {
    // allowedUserIds가 비어있으면 모든 사용자 허용 (기존 호환)
    if (this.allowedUserIds.size === 0) return true;
    return this.allowedUserIds.has(userId);
  }

  async connect(config: PlatformConfig): Promise<void> {
    this.bot = new Telegraf(config.token);

    // 허용 사용자 목록 설정
    if (config.allowedUserIds?.length) {
      this.allowedUserIds = new Set(config.allowedUserIds);
      console.log(`[Telegram] 🔒 인증 모드: ${this.allowedUserIds.size}명 허용`);
    } else {
      console.log(`[Telegram] ⚠️  인증 미설정: 모든 사용자 허용`);
    }

    // 버튼 콜백 핸들링
    this.bot.on('callback_query', async (ctx) => {
      if (!this.actionHandler) return;

      // 인증 검사
      const userId = String(ctx.from.id);
      if (!this.isAuthorized(userId)) {
        await ctx.answerCbQuery('🔒 인증되지 않은 사용자입니다.');
        return;
      }

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
      // 인증 검사
      const userId = String(ctx.from.id);
      if (!this.isAuthorized(userId)) {
        console.log(`[Telegram] 🚫 미인증 사용자 차단: ${userId}`);
        await ctx.reply('🔒 인증되지 않은 사용자입니다. 관리자에게 문의하세요.');
        return;
      }

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

    // Telegram 명령어 메뉴 등록
    await this.bot.telegram.setMyCommands([
      { command: 'new', description: '새 대화 시작 (세션 초기화)' },
      { command: 'sessions', description: 'Claude Code 세션 목록' },
      { command: 'connect', description: '기존 세션에 연결 (/connect id)' },
      { command: 'disconnect', description: '세션 연결 해제' },
      { command: 'session', description: '현재 세션 정보' },
      { command: 'claude', description: 'Claude에 질문 (/claude 질문)' },
      { command: 'codex', description: 'Codex에 질문 (/codex 질문)' },
      { command: 'help', description: '사용 가능한 명령어 목록' },
      { command: 'status', description: '루프 상태 확인' },
      { command: 'start', description: '작업 시작 (/start 작업내용)' },
      { command: 'stop', description: '루프 중지' },
      { command: 'cancel', description: '루프 취소' },
    ]);
    console.log('[Telegram] 명령어 메뉴 등록 완료');

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
