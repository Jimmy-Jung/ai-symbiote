/**
 * 파일시스템 감시자 — chokidar 기반
 * @author JunyoungJung
 * @date 2026-04-02
 *
 * messenger/ 하위 디렉터리를 감시하여 새 JSON 파일이 생기면 핸들러를 호출한다.
 */

import { watch, type FSWatcher } from 'chokidar';
import { join, basename } from 'node:path';
import { readJson, markFile, fileAgeMs, listJsonFiles } from './utils/file-protocol.js';

const ONE_HOUR_MS = 60 * 60 * 1000;
const FILE_HANDLER_TIMEOUT_MS = 15 * 1000;

export type FileHandler = (filePath: string, data: unknown) => Promise<void>;

export interface WatcherOptions {
  messengerDir: string;
  onNotification: FileHandler;
  onApprovalRequest: FileHandler;
  onCommand: FileHandler;
}

export class BridgeWatcher {
  private watcher: FSWatcher | null = null;
  private scanTimer: NodeJS.Timeout | null = null;
  private readonly inFlight = new Set<string>();
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
      usePolling: true,
      interval: 500,
      awaitWriteFinish: { stabilityThreshold: 300, pollInterval: 100 },
    });

    this.watcher.on('add', (filePath) => {
      console.log('[Watcher] 파일 감지:', filePath);
      void this.handleNewFile(filePath);
    });
    this.watcher.on('ready', () => {
      console.log('[Watcher] 초기 스캔 완료');
      void this.scanPendingFiles();

      this.scanTimer = setInterval(() => {
        void this.scanPendingFiles();
      }, 2000);
      this.scanTimer.unref();
    });
    this.watcher.on('error', (err) => console.error('[Watcher] 오류:', err));
  }

  async stop(): Promise<void> {
    if (this.scanTimer) {
      clearInterval(this.scanTimer);
      this.scanTimer = null;
    }

    if (this.watcher) {
      await this.watcher.close();
      this.watcher = null;
    }
  }

  private async handleNewFile(filePath: string): Promise<void> {
    const name = basename(filePath);
    if (!name.endsWith('.json')) return;
    if (this.inFlight.has(filePath)) return;

    this.inFlight.add(filePath);

    try {
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

      if (filePath.includes('/notifications/')) {
        await this.withTimeout(
          this.handlers.onNotification(filePath, data),
          `notification timeout: ${filePath}`,
        );
      } else if (filePath.includes('/approvals/') && name.endsWith('_request.json')) {
        await this.withTimeout(
          this.handlers.onApprovalRequest(filePath, data),
          `approval timeout: ${filePath}`,
        );
      } else if (filePath.includes('/commands/')) {
        await this.withTimeout(
          this.handlers.onCommand(filePath, data),
          `command timeout: ${filePath}`,
        );
      }
    } catch (err) {
      console.error(`[Watcher] 파일 처리 실패: ${filePath}`, err);
    } finally {
      this.inFlight.delete(filePath);
    }
  }

  private async scanPendingFiles(): Promise<void> {
    const { messengerDir } = this.handlers;
    const targets = [
      join(messengerDir, 'notifications'),
      join(messengerDir, 'approvals'),
      join(messengerDir, 'commands'),
    ];

    for (const dir of targets) {
      const files = await listJsonFiles(dir);
      for (const filePath of files) {
        await this.handleNewFile(filePath);
      }
    }
  }

  private async withTimeout<T>(promise: Promise<T>, message: string): Promise<T> {
    let timer: NodeJS.Timeout | null = null;

    try {
      return await Promise.race([
        promise,
        new Promise<never>((_, reject) => {
          timer = setTimeout(() => reject(new Error(message)), FILE_HANDLER_TIMEOUT_MS);
          timer.unref();
        }),
      ]);
    } finally {
      if (timer) {
        clearTimeout(timer);
      }
    }
  }
}
