/**
 * AI CLI 릴레이 핸들러 — Claude / Codex 지원
 * @author JunyoungJung
 * @date 2026-04-03
 *
 * 루프 비활성 시 Telegram 메시지를 AI CLI에 전달하고 응답을 회신한다.
 * /claude, /codex 명령으로 CLI를 명시적 선택하거나, 자유 텍스트는 기본 CLI 사용.
 */

import { spawn, exec } from 'node:child_process';
import { readFile, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { promisify } from 'node:util';
import type { MessengerAdapter, UserMessage } from '../adapters/types.js';

const execAsync = promisify(exec);

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
    const preview = msg.text.length > 60 ? msg.text.slice(0, 60) + '…' : msg.text;
    this.busy = true;

    console.log(`[Relay] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
    console.log(`[Relay] 💬 질문: "${msg.text}"`);
    console.log(`[Relay] 🚀 ${cli} 실행 시작`);
    this.notify('Telegram 릴레이', `${cli} 실행 중: ${preview}`);
    await this.reply(msg.channelId, `🤖 ${cli} 처리 중...`);

    const startTime = Date.now();
    try {
      const result = cli === 'codex'
        ? await this.callCodex(msg.text)
        : await this.callClaude(msg.text);
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
      console.log(`[Relay] ✅ 완료 (${elapsed}s, ${result.length}자)`);
      console.log(`[Relay] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
      this.notify('Telegram 릴레이', `완료 (${elapsed}s)`);

      const chunks = this.splitMessage(result);
      for (const chunk of chunks) {
        await this.reply(msg.channelId, chunk);
      }
    } catch (err) {
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
      const errorMsg = err instanceof Error ? err.message : String(err);
      console.log(`[Relay] ❌ 오류 (${elapsed}s): ${errorMsg.slice(0, 200)}`);
      console.log(`[Relay] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
      this.notify('Telegram 릴레이', `오류: ${errorMsg.slice(0, 100)}`);
      await this.reply(msg.channelId, `❌ ${cli} 오류: ${errorMsg.slice(0, 500)}`);
    } finally {
      this.busy = false;
    }
  }

  /** macOS 알림 센터로 데스크톱 알림 전송 */
  private notify(title: string, body: string): void {
    const escaped = (s: string) => s.replace(/"/g, '\\"');
    const script = `display notification "${escaped(body)}" with title "${escaped(title)}"`;
    execAsync(`osascript -e '${script.replace(/'/g, "'\\''")}'`).catch(() => {});
  }

  /** spawn 기반 Claude CLI 호출 — stdout/stderr 실시간 로그 출력 */
  private callClaude(prompt: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const args = ['-p', prompt, '--output-format', 'text'];
      const child = spawn('claude', args, {
        timeout: 120_000,
        cwd: this.projectDir ?? process.cwd(),
        env: { ...process.env, LANG: 'ko_KR.UTF-8' },
        stdio: ['ignore', 'pipe', 'pipe'],
      });

      const stdoutChunks: Buffer[] = [];
      const stderrChunks: Buffer[] = [];

      child.stdout.on('data', (chunk: Buffer) => {
        stdoutChunks.push(chunk);
        const lines = chunk.toString().split('\n').filter(Boolean);
        for (const line of lines) {
          const trimmed = line.length > 120 ? line.slice(0, 120) + '…' : line;
          console.log(`[Relay] 📝 ${trimmed}`);
        }
      });

      child.stderr.on('data', (chunk: Buffer) => {
        stderrChunks.push(chunk);
        const text = chunk.toString().trim();
        if (text) {
          console.log(`[Relay] ⚠️  ${text.slice(0, 200)}`);
        }
      });

      child.on('close', (code) => {
        const stdout = Buffer.concat(stdoutChunks).toString().trim();
        const stderr = Buffer.concat(stderrChunks).toString().trim();

        if (code !== 0 && !stdout) {
          reject(new Error(stderr || `프로세스 종료 코드: ${code}`));
          return;
        }
        resolve(stdout || '(빈 응답)');
      });

      child.on('error', (err) => {
        reject(err);
      });
    });
  }

  /** spawn 기반 Codex CLI 호출 — stdout/stderr 실시간 로그 출력 */
  private callCodex(prompt: string): Promise<string> {
    const tmpFile = join(tmpdir(), `codex-out-${randomBytes(4).toString('hex')}.txt`);

    return new Promise((resolve, reject) => {
      const args = ['exec', prompt, '-o', tmpFile];
      const child = spawn('codex', args, {
        timeout: 180_000,
        cwd: this.projectDir ?? process.cwd(),
        env: { ...process.env, LANG: 'ko_KR.UTF-8' },
        stdio: ['ignore', 'pipe', 'pipe'],
      });

      const stdoutChunks: Buffer[] = [];
      const stderrChunks: Buffer[] = [];

      child.stdout.on('data', (chunk: Buffer) => {
        stdoutChunks.push(chunk);
        const lines = chunk.toString().split('\n').filter(Boolean);
        for (const line of lines) {
          const trimmed = line.length > 120 ? line.slice(0, 120) + '…' : line;
          console.log(`[Relay] 📝 ${trimmed}`);
        }
      });

      child.stderr.on('data', (chunk: Buffer) => {
        stderrChunks.push(chunk);
      });

      child.on('close', async (code) => {
        const stdout = Buffer.concat(stdoutChunks).toString().trim();
        const stderr = Buffer.concat(stderrChunks).toString().trim();

        // codex exec는 -o 파일에 최종 응답을 기록
        let output = '';
        try {
          output = (await readFile(tmpFile, 'utf-8')).trim();
          await unlink(tmpFile);
        } catch {
          output = stdout;
        }

        if (!output && code !== 0) {
          reject(new Error(stderr || `프로세스 종료 코드: ${code}`));
          return;
        }
        resolve(output || '(빈 응답)');
      });

      child.on('error', (err) => {
        reject(err);
      });
    });
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
