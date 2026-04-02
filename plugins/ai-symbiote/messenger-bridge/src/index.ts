/**
 * Messenger Bridge 진입점
 * @author JunyoungJung
 * @date 2026-04-02
 *
 * 사용법: node dist/index.js --state-dir ~/ai-symbiote/{slug}
 */

import { writeFile, readFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { loadConfig, messengerDir } from './config.js';
import { BridgeWatcher } from './watcher.js';
import { NotificationHandler } from './handlers/notification.js';
import { ApprovalHandler } from './handlers/approval.js';
import { SessionControlHandler } from './handlers/session-control.js';
import { SlackAdapter } from './adapters/slack.js';
import { DiscordAdapter } from './adapters/discord.js';
import { TelegramAdapter } from './adapters/telegram.js';
import type { MessengerAdapter, PlatformConfig, Platform } from './adapters/types.js';

// ── CLI 인자 파싱 ──

function parseArgs(): { stateDir: string } {
  const args = process.argv.slice(2);
  const idx = args.indexOf('--state-dir');
  if (idx === -1 || !args[idx + 1]) {
    console.error('사용법: node dist/index.js --state-dir <path>');
    process.exit(1);
  }
  return { stateDir: args[idx + 1] };
}

// ── 어댑터 팩토리 ──

function createAdapter(platform: Platform): MessengerAdapter {
  switch (platform) {
    case 'slack': return new SlackAdapter();
    case 'discord': return new DiscordAdapter();
    case 'telegram': return new TelegramAdapter();
  }
}

function buildPlatformConfig(config: ReturnType<typeof import('./config.js')['loadConfig']> extends Promise<infer T> ? NonNullable<T> : never): PlatformConfig {
  const p = config.platform;
  if (p === 'slack') {
    return {
      platform: 'slack',
      token: config.slack!.botToken,
      channelId: config.slack!.channelId,
      signingSecret: config.slack!.signingSecret,
      appToken: config.slack!.appToken,
    };
  }
  if (p === 'discord') {
    return {
      platform: 'discord',
      token: config.discord!.token,
      channelId: config.discord!.channelId,
    };
  }
  return {
    platform: 'telegram',
    token: config.telegram!.token,
    channelId: config.telegram!.chatId,
  };
}

// ── 메인 ──

async function main(): Promise<void> {
  const { stateDir } = parseArgs();
  const msgDir = messengerDir(stateDir);

  // 설정 로드
  const config = await loadConfig(stateDir);
  if (!config) {
    console.error('[Bridge] config.json을 찾을 수 없습니다:', join(msgDir, 'config.json'));
    process.exit(1);
  }
  if (!config.enabled) {
    console.error('[Bridge] 메신저 브릿지가 비활성화되어 있습니다.');
    process.exit(0);
  }

  console.log(`[Bridge] 플랫폼: ${config.platform}`);
  console.log(`[Bridge] 상태 디렉터리: ${stateDir}`);

  // PID 파일 기록
  const pidPath = join(msgDir, 'bot.pid');
  await writeFile(pidPath, String(process.pid), 'utf-8');

  // 어댑터 생성 및 연결
  const adapter = createAdapter(config.platform);
  const platformConfig = buildPlatformConfig(config);
  await adapter.connect(platformConfig);
  console.log(`[Bridge] ${config.platform} 연결 완료`);

  // 핸들러 생성
  const notificationHandler = new NotificationHandler(adapter, config);
  const approvalHandler = new ApprovalHandler(adapter, config, msgDir);
  const sessionControlHandler = new SessionControlHandler(adapter, stateDir, msgDir);

  // 어댑터 이벤트 등록
  adapter.onAction(async (action) => {
    await approvalHandler.handleUserAction(action);
  });

  adapter.onMessage(async (msg) => {
    await sessionControlHandler.handleMessage(msg);
  });

  // 파일 감시 시작
  const watcher = new BridgeWatcher({
    messengerDir: msgDir,
    onNotification: (fp, data) => notificationHandler.handle(fp, data),
    onApprovalRequest: (fp, data) => approvalHandler.handleRequest(fp, data),
    onCommand: async () => {
      // 커맨드 파일은 봇이 작성하는 것이므로 여기서는 처리하지 않음
      // Claude Code 측에서 폴링하여 소비
    },
  });
  watcher.start();
  console.log('[Bridge] 파일 감시 시작');

  // 그레이스풀 셧다운
  const shutdown = async (signal: string) => {
    console.log(`\n[Bridge] ${signal} 수신, 종료 중...`);
    approvalHandler.cleanup();
    await watcher.stop();
    await adapter.disconnect();
    try { await unlink(pidPath); } catch { /* 이미 삭제됨 */ }
    process.exit(0);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  console.log('[Bridge] 메신저 브릿지 가동 완료. Ctrl+C로 종료.');
}

main().catch((err) => {
  console.error('[Bridge] 치명적 오류:', err);
  process.exit(1);
});
