/**
 * Stage 1: 알림 핸들러
 * @author JunyoungJung
 * @date 2026-04-02
 *
 * notifications/ 디렉터리의 JSON을 읽어 메신저로 전송하고 .sent로 마킹한다.
 */

import type { MessengerAdapter } from '../adapters/types.js';
import type { MessengerConfig } from '../config.js';
import { formatNotification, toPlainText } from '../formatters/messages.ko.js';
import { markFile } from '../utils/file-protocol.js';

export class NotificationHandler {
  constructor(
    private adapter: MessengerAdapter,
    private config: MessengerConfig,
  ) {}

  async handle(filePath: string, data: unknown): Promise<void> {
    const raw = data as { event: string; taskFolder: string; data: Record<string, unknown> };

    // 설정에 따라 특정 이벤트 스킵
    if (!this.config.preferences.notifyOnPhaseChange && raw.event === 'phase_change') return;
    if (!this.config.preferences.notifyOnIterationComplete && raw.event === 'iteration_complete') return;

    const msg = formatNotification(raw);
    const channelId = this.getChannelId();
    await this.adapter.sendNotification(channelId, msg);
    await markFile(filePath, 'sent');
  }

  private getChannelId(): string {
    const p = this.config.platform;
    if (p === 'slack') return this.config.slack!.channelId;
    if (p === 'discord') return this.config.discord!.channelId;
    return this.config.telegram!.chatId;
  }
}
