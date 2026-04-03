/**
 * 파일시스템 감시자 — chokidar 기반
 * @author JunyoungJung
 * @date 2026-04-02
 *
 * messenger/ 하위 디렉터리를 감시하여 새 JSON 파일이 생기면 핸들러를 호출한다.
 */

import { watch, type FSWatcher } from 'chokidar';
import { join, basename } from 'node:path';
import { readJson, markFile, fileAgeMs } from './utils/file-protocol.js';

const ONE_HOUR_MS = 60 * 60 * 1000;

export type FileHandler = (filePath: string, data: unknown) => Promise<void>;

export interface WatcherOptions {
  messengerDir: string;
  onNotification: FileHandler;
  onApprovalRequest: FileHandler;
  onCommand: FileHandler;
}

export class BridgeWatcher {
  private watcher: FSWatcher | null = null;
  private handlers: WatcherOptions;

  constructor(handlers: WatcherOptions) {
    this.handlers = handlers;
  }

  start(): void {
    const { messengerDir } = this.handlers;

    const watchPaths = [
      join(messengerDir, 'notifications'),
      join(messengerDir, 'approvals'),
      join(messengerDir, 'commands'),
    ];

    this.watcher = watch(watchPaths, {
      ignoreInitial: false,
      awaitWriteFinish: { stabilityThreshold: 300, pollInterval: 100 },
    });

    this.watcher.on('add', (filePath) => {
      console.log('[Watcher] 파일 감지:', filePath);
      this.handleNewFile(filePath);
    });
    this.watcher.on('error', (err) => console.error('[Watcher] 오류:', err));
  }

  async stop(): Promise<void> {
    if (this.watcher) {
      await this.watcher.close();
      this.watcher = null;
    }
  }

  private async handleNewFile(filePath: string): Promise<void> {
    const name = basename(filePath);
    if (!name.endsWith('.json')) return;

    // 만료 처리: 1시간 초과 파일은 스킵
    try {
      const age = await fileAgeMs(filePath);
      if (age > ONE_HOUR_MS) {
        await markFile(filePath, 'expired');
        return;
      }
    } catch {
      return;
    }

    const data = await readJson(filePath);
    if (!data) return;

    try {
      if (filePath.includes('/notifications/')) {
        await this.handlers.onNotification(filePath, data);
      } else if (filePath.includes('/approvals/') && name.endsWith('_request.json')) {
        await this.handlers.onApprovalRequest(filePath, data);
      } else if (filePath.includes('/commands/')) {
        await this.handlers.onCommand(filePath, data);
      }
    } catch (err) {
      console.error(`[Watcher] 파일 처리 실패: ${filePath}`, err);
    }
  }
}
