/**
 * AI CLI 릴레이 핸들러 — Claude / Codex 지원
 * @author JunyoungJung
 * @date 2026-04-03
 *
 * 루프 비활성 시 Telegram 메시지를 AI CLI에 전달하고 응답을 회신한다.
 * /claude, /codex 명령으로 CLI를 명시적 선택하거나, 자유 텍스트는 기본 CLI 사용.
 */

import { execFile } from 'node:child_process';
import { readFile, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { promisify } from 'node:util';
import type { MessengerAdapter, UserMessage } from '../adapters/types.js';

const execFileAsync = promisify(execFile);

/** Telegram 메시지 길이 제한 (4096자) */
const TELEGRAM_MAX_LENGTH = 4000;

export type AIBackend = 'claude' | 'codex';

export class ClaudeRelayHandler {
  private busy = false;

  constructor(
    private adapter: MessengerAdapter,
    private projectDir: string | undefined,
    private defaultBackend: AIBackend = 'claude',
  ) {}

  /** 메시지를 AI CLI에 전달하고 응답을 회신 */
  async handle(msg: UserMessage, backend?: AIBackend): Promise<void> {
    if (this.busy) {
      await this.reply(msg.channelId, '⏳ 이전 요청을 처리 중입니다. 잠시 후 다시 시도해주세요.');
      return;
    }

    const cli = backend ?? this.defaultBackend;
    this.busy = true;
    await this.reply(msg.channelId, `🤖 ${cli} 처리 중...`);

    try {
      const result = cli === 'codex'
        ? await this.callCodex(msg.text)
        : await this.callClaude(msg.text);
      const chunks = this.splitMessage(result);
      for (const chunk of chunks) {
        await this.reply(msg.channelId, chunk);
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      await this.reply(msg.channelId, `❌ ${cli} 오류: ${errorMsg.slice(0, 500)}`);
    } finally {
      this.busy = false;
    }
  }

  private async callClaude(prompt: string): Promise<string> {
    const args = ['-p', prompt, '--output-format', 'text'];
    if (this.projectDir) {
      args.push('--cwd', this.projectDir);
    }

    const { stdout, stderr } = await execFileAsync('claude', args, {
      timeout: 120_000,
      maxBuffer: 1024 * 1024,
      env: { ...process.env, LANG: 'ko_KR.UTF-8' },
    });

    const output = stdout.trim();
    if (!output && stderr.trim()) {
      throw new Error(stderr.trim());
    }
    return output || '(빈 응답)';
  }

  private async callCodex(prompt: string): Promise<string> {
    const tmpFile = join(tmpdir(), `codex-out-${randomBytes(4).toString('hex')}.txt`);
    const args = ['exec', prompt, '-o', tmpFile];

    const execOpts: Record<string, unknown> = {
      timeout: 180_000,
      maxBuffer: 1024 * 1024,
      env: { ...process.env, LANG: 'ko_KR.UTF-8' },
      cwd: this.projectDir ?? process.cwd(),
    };

    const { stdout, stderr } = await execFileAsync('codex', args, execOpts);

    // codex exec는 -o 파일에 최종 응답을 기록
    let output = '';
    try {
      output = (await readFile(tmpFile, 'utf-8')).trim();
      await unlink(tmpFile);
    } catch {
      // -o 파일이 없으면 stdout 사용
      output = stdout.trim();
    }

    if (!output && stderr.trim()) {
      throw new Error(stderr.trim());
    }
    return output || '(빈 응답)';
  }

  /** 긴 메시지를 Telegram 제한에 맞게 분할 */
  private splitMessage(text: string): string[] {
    if (text.length <= TELEGRAM_MAX_LENGTH) return [text];

    const chunks: string[] = [];
    let remaining = text;
    while (remaining.length > 0) {
      if (remaining.length <= TELEGRAM_MAX_LENGTH) {
        chunks.push(remaining);
        break;
      }
      let cutAt = remaining.lastIndexOf('\n', TELEGRAM_MAX_LENGTH);
      if (cutAt <= 0) cutAt = TELEGRAM_MAX_LENGTH;
      chunks.push(remaining.slice(0, cutAt));
      remaining = remaining.slice(cutAt).trimStart();
    }
    return chunks;
  }

  private async reply(channelId: string, text: string): Promise<void> {
    await this.adapter.sendNotification(channelId, {
      title: '',
      body: text,
      level: 'info',
      timestamp: new Date().toISOString(),
    });
  }
}
