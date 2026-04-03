/**
 * AI CLI 릴레이 핸들러 — Claude / Codex 지원 (세션 연동)
 * @author JunyoungJung
 * @date 2026-04-03
 *
 * Telegram 메시지를 Claude CLI에 전달하고 응답을 회신한다.
 * --resume 플래그로 세션 ID를 추적하여 Claude Code 터미널과 동일한 대화 경험을 제공한다.
 *
 * 세션 명령:
 * /new            — 새 대화 시작 (세션 초기화)
 * /session        — 현재 세션 정보 표시
 * /connect <id>   — 기존 Claude Code 세션에 연결
 * /disconnect     — 세션 연결 해제
 */

import { spawn, exec } from 'node:child_process';
import { readFile, readdir, unlink } from 'node:fs/promises';
import { tmpdir, homedir } from 'node:os';
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
  /** 현재 Claude 세션 ID */
  private sessionId: string | null = null;
  /** 현재 세션의 메시지 카운트 */
  private messageCount = 0;
  /** 세션 시작 시각 */
  private sessionStartedAt: Date | null = null;

  constructor(
    private adapter: MessengerAdapter,
    private projectDir: string | undefined,
    private defaultBackend: AIBackend = 'claude',
  ) {}

  /** 새 세션 시작 (세션 초기화) */
  async resetSession(channelId: string): Promise<void> {
    const hadSession = this.sessionId !== null;
    this.sessionId = null;
    this.messageCount = 0;
    this.sessionStartedAt = null;
    console.log(`[Relay] 🔄 세션 초기화`);

    if (hadSession) {
      await this.reply(channelId, '🔄 새 대화를 시작합니다. 이전 컨텍스트가 초기화되었습니다.');
    } else {
      await this.reply(channelId, '🔄 새 대화를 시작합니다.');
    }
  }

  /** 기존 세션에 연결 */
  async connectSession(channelId: string, sessionId: string): Promise<void> {
    this.sessionId = sessionId;
    this.messageCount = 0;
    this.sessionStartedAt = new Date();
    console.log(`[Relay] 🔗 세션 연결: ${sessionId}`);
    await this.reply(channelId, `🔗 세션에 연결되었습니다.\n\`${sessionId}\`\n\n이제 메시지를 보내면 이 세션으로 전달됩니다.`);
  }

  /** 세션 연결 해제 */
  async disconnectSession(channelId: string): Promise<void> {
    if (!this.sessionId) {
      await this.reply(channelId, '연결된 세션이 없습니다.');
      return;
    }
    const oldId = this.sessionId;
    this.sessionId = null;
    this.messageCount = 0;
    this.sessionStartedAt = null;
    console.log(`[Relay] 🔌 세션 연결 해제: ${oldId}`);
    await this.reply(channelId, `🔌 세션 연결이 해제되었습니다.\n다음 메시지는 새 세션으로 시작됩니다.`);
  }

  /** 현재 세션 정보 표시 */
  async showSessionInfo(channelId: string): Promise<void> {
    if (!this.sessionId) {
      await this.reply(channelId, '📊 활성 세션 없음\n\n메시지를 보내면 새 세션이 시작됩니다.\n기존 세션에 연결하려면 /connect <session-id>');
      return;
    }

    const elapsed = this.sessionStartedAt
      ? Math.round((Date.now() - this.sessionStartedAt.getTime()) / 1000)
      : 0;
    const minutes = Math.floor(elapsed / 60);
    const seconds = elapsed % 60;

    const info = [
      '📊 세션 정보',
      `├ ID: \`${this.sessionId}\``,
      `├ 상태: 활성`,
      `├ 메시지: ${this.messageCount}회`,
      `├ 경과: ${minutes}분 ${seconds}초`,
      `└ 백엔드: ${this.defaultBackend}`,
      '',
      '💡 /new — 새 대화 | /disconnect — 연결 해제',
    ].join('\n');

    await this.reply(channelId, info);
  }

  /** Claude Code 세션 목록 표시 */
  async listSessions(channelId: string, filterCwd?: string): Promise<void> {
    try {
      const sessionsDir = join(homedir(), '.claude', 'sessions');
      const projectsDir = join(homedir(), '.claude', 'projects');
      const files = await readdir(sessionsDir);

      interface SessionInfo {
        sessionId: string;
        cwd: string;
        startedAt: number;
        summary: string;
      }

      const sessions: SessionInfo[] = [];
      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await readFile(join(sessionsDir, file), 'utf-8');
          const data = JSON.parse(content);
          if (filterCwd && !data.cwd?.includes(filterCwd)) continue;

          // 대화 요약 추출
          const projKey = `-${data.cwd.replace(/\//g, '-').slice(1)}`;
          const jsonlPath = join(projectsDir, projKey, `${data.sessionId}.jsonl`);
          const summary = await this.extractSessionSummary(jsonlPath);

          sessions.push({
            sessionId: data.sessionId ?? '',
            cwd: data.cwd ?? '',
            startedAt: data.startedAt ?? 0,
            summary,
          });
        } catch {
          // 파싱 실패한 파일 무시
        }
      }

      // 최신순 정렬, 상위 10개
      sessions.sort((a, b) => b.startedAt - a.startedAt);
      const top = sessions.slice(0, 10);

      if (top.length === 0) {
        await this.reply(channelId, '📋 세션을 찾을 수 없습니다.');
        return;
      }

      const lines = ['📋 Claude Code 세션 목록', ''];
      for (const s of top) {
        const date = new Date(s.startedAt);
        const timeStr = `${date.getMonth() + 1}/${date.getDate()} ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
        const project = s.cwd.split('/').pop() ?? s.cwd;
        const active = s.sessionId === this.sessionId ? ' ✓' : '';
        const summaryText = s.summary ? `\n  → ${s.summary}` : '';
        lines.push(`\`${s.sessionId.slice(0, 8)}\` ${timeStr} *${project}*${active}${summaryText}`);
      }
      lines.push('');
      lines.push('연결: /connect <앞 8자>');

      await this.reply(channelId, lines.join('\n'));
    } catch (err) {
      await this.reply(channelId, `❌ 세션 목록 조회 실패: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  /** 세션 JSONL에서 첫 유의미한 사용자 메시지 추출 */
  private async extractSessionSummary(jsonlPath: string): Promise<string> {
    try {
      const content = await readFile(jsonlPath, 'utf-8');
      const lines = content.split('\n').filter(Boolean);

      for (const line of lines) {
        const d = JSON.parse(line);
        if (d.type !== 'user') continue;

        const msg = d.message;
        if (!msg) continue;
        const raw = typeof msg.content === 'string'
          ? msg.content
          : Array.isArray(msg.content)
            ? msg.content.find((c: any) => c.type === 'text')?.text ?? ''
            : '';

        if (!raw) continue;

        // command-message 태그에서 스킬명 추출
        const cm = raw.match(/<command-message>([^<]+)<\/command-message>/);
        if (cm) return `/${cm[1].trim()}`;

        // XML/ANSI 제거 후 정제
        let text = raw
          .replace(/<[^>]+>/g, '')
          .replace(/\x1b\[[0-9;]*m/g, '')
          .replace(/\n+/g, ' ')
          .trim();

        // 비실질적 메시지 skip
        if (text.length < 5) continue;
        if (/^(Base directory|Caveat:|ARGUMENTS:|\/model|\/Users\/|Set model|clear$|setup$|reload)/i.test(text)) continue;

        return text.slice(0, 50);
      }
    } catch {
      // 파일 없음 또는 파싱 실패
    }
    return '';
  }

  /** 짧은 세션 ID(8자)를 전체 ID로 확장 */
  async resolveSessionId(partial: string): Promise<string | null> {
    try {
      const sessionsDir = join(homedir(), '.claude', 'sessions');
      const files = await readdir(sessionsDir);

      for (const file of files) {
        if (!file.endsWith('.json')) continue;
        try {
          const content = await readFile(join(sessionsDir, file), 'utf-8');
          const data = JSON.parse(content);
          if (data.sessionId?.startsWith(partial)) {
            return data.sessionId;
          }
        } catch {
          // ignore
        }
      }
    } catch {
      // ignore
    }
    return null;
  }

  /** 메시지를 AI CLI에 전달하고 응답을 회신 */
  async handle(msg: UserMessage, backend?: AIBackend): Promise<void> {
    if (this.busy) {
      await this.reply(msg.channelId, '⏳ 이전 요청을 처리 중입니다. 잠시 후 다시 시도해주세요.');
      return;
    }

    const cli = backend ?? this.defaultBackend;
    const preview = msg.text.length > 60 ? msg.text.slice(0, 60) + '…' : msg.text;
    this.busy = true;

    const mode = this.sessionId ? `세션 이어감` : '새 세션';
    console.log(`[Relay] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
    console.log(`[Relay] 💬 질문: "${msg.text}"`);
    console.log(`[Relay] 🚀 ${cli} 실행 (${mode}, #${this.messageCount + 1})${this.sessionId ? ` [${this.sessionId.slice(0, 8)}…]` : ''}`);
    this.notify('Telegram 릴레이', `${cli}: ${preview}`);
    await this.reply(msg.channelId, `🤖 ${cli} 처리 중... (${mode})`);

    const startTime = Date.now();
    try {
      const result = cli === 'codex'
        ? await this.callCodex(msg.text)
        : await this.callClaude(msg.text);
      const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

      // 세션 시작 시각 기록
      if (!this.sessionStartedAt) {
        this.sessionStartedAt = new Date();
      }
      this.messageCount++;

      console.log(`[Relay] ✅ 완료 (${elapsed}s, ${result.length}자, 세션 #${this.messageCount})`);
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

  /**
   * spawn 기반 Claude CLI 호출
   * - 첫 호출: --output-format json 으로 session_id 캡처
   * - 이후: --resume <session_id> 로 세션 이어감
   */
  private callClaude(prompt: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const isNewSession = !this.sessionId;
      const args = ['-p', prompt];

      if (this.sessionId) {
        // 기존 세션 이어감
        args.push('--resume', this.sessionId, '--output-format', 'text');
      } else {
        // 새 세션 — JSON으로 session_id 캡처
        args.push('--output-format', 'json');
      }

      console.log(`[Relay] 🔧 claude ${args.map(a => a.includes(' ') ? `"${a}"` : a).join(' ')}`);

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
        if (!isNewSession) {
          // text 모드일 때만 실시간 로그
          const lines = chunk.toString().split('\n').filter(Boolean);
          for (const line of lines) {
            const trimmed = line.length > 120 ? line.slice(0, 120) + '…' : line;
            console.log(`[Relay] 📝 ${trimmed}`);
          }
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

        if (isNewSession) {
          // JSON 출력에서 session_id와 응답 텍스트 추출
          const { sessionId, text } = this.parseJsonOutput(stdout);
          if (sessionId) {
            this.sessionId = sessionId;
            console.log(`[Relay] 🔗 세션 생성됨: ${sessionId}`);
          }
          // 응답 텍스트를 로그에 출력
          const lines = text.split('\n').filter(Boolean);
          for (const line of lines) {
            const trimmed = line.length > 120 ? line.slice(0, 120) + '…' : line;
            console.log(`[Relay] 📝 ${trimmed}`);
          }
          resolve(text || '(빈 응답)');
        } else {
          resolve(stdout || '(빈 응답)');
        }
      });

      child.on('error', (err) => {
        reject(err);
      });
    });
  }

  /** JSON 출력에서 session_id와 result 텍스트 추출 */
  private parseJsonOutput(raw: string): { sessionId: string | null; text: string } {
    try {
      // claude --output-format json 은 JSON 배열을 출력
      const events = JSON.parse(raw);
      let sessionId: string | null = null;
      let text = '';

      for (const event of events) {
        if (event.type === 'system' && event.session_id) {
          sessionId = event.session_id;
        }
        if (event.type === 'result' && event.result) {
          text = event.result;
        }
      }

      return { sessionId, text };
    } catch {
      // JSON 파싱 실패 시 원본 텍스트 반환
      return { sessionId: null, text: raw };
    }
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
