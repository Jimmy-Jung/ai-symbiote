/**
 * Stage 3: 세션 제어 핸들러
 * @author JunyoungJung
 * @date 2026-04-02
 *
 * 메신저에서 받은 텍스트 명령을 파싱하여:
 * - stop/resume/cancel → ralph-state.md 직접 수정
 * - start/instruct → commands/ 에 JSON 파일 작성
 * - status → 상태를 읽어 메신저로 응답
 */

import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import type { MessengerAdapter, UserMessage } from '../adapters/types.js';
import { writeJsonAtomic, ensureDir, fileTimestamp } from '../utils/file-protocol.js';
import { findActiveTaskFolders, parseRalphState, readNotepad } from '../utils/state-reader.js';
import { formatStatusMessage } from '../formatters/messages.ko.js';
import { ClaudeRelayHandler, type AIBackend } from './claude-relay.js';

type Command = 'start' | 'stop' | 'resume' | 'cancel' | 'status' | 'instruct' | 'chat' | 'claude' | 'codex';

interface ParsedCommand {
  command: Command;
  args: string;
}

interface CommandFile {
  command: Command;
  timestamp: string;
  args: Record<string, string>;
  status: 'pending';
}

export class SessionControlHandler {
  private claudeRelay: ClaudeRelayHandler;

  constructor(
    private adapter: MessengerAdapter,
    private stateDir: string,
    private messengerDir: string,
    projectDir?: string,
    defaultBackend?: AIBackend,
  ) {
    this.claudeRelay = new ClaudeRelayHandler(adapter, projectDir, defaultBackend);
  }

  /** 메신저 텍스트 메시지를 명령으로 처리 */
  async handleMessage(msg: UserMessage): Promise<void> {
    const parsed = this.parseCommand(msg.text);
    if (!parsed) {
      // 명령이 아닌 자유 텍스트 → 루프 활성 여부에 따라 분기
      const loopActive = await this.isLoopActive();
      if (loopActive) {
        await this.writeCommand('instruct', { instruction: msg.text });
        await this.adapter.sendNotification(msg.channelId, {
          title: '지시 수신',
          body: `"${msg.text.slice(0, 100)}" — 다음 반복에 주입됩니다.`,
          level: 'info',
          timestamp: new Date().toISOString(),
        });
      } else {
        await this.claudeRelay.handle(msg);
      }
      return;
    }

    switch (parsed.command) {
      case 'status':
        await this.handleStatus(msg.channelId);
        break;
      case 'stop':
        await this.modifyRalphState({ active: 'false' });
        await this.reply(msg.channelId, '⏸️ 루프를 중지합니다. 다음 반복에서 감지됩니다.');
        break;
      case 'resume':
        await this.modifyRalphState({ active: 'true' });
        await this.reply(msg.channelId, '▶️ 루프를 재개합니다.');
        break;
      case 'cancel':
        await this.modifyRalphState({ active: 'false', phase: 'cancelled' });
        await this.reply(msg.channelId, '❌ 루프를 취소했습니다.');
        break;
      case 'start':
        await this.writeCommand('start', { task: parsed.args });
        await this.reply(msg.channelId, `🚀 작업 시작 요청: "${parsed.args}"\n다음 세션에서 auto-loop으로 시작됩니다.`);
        break;
      case 'instruct':
        await this.writeCommand('instruct', { instruction: parsed.args });
        await this.reply(msg.channelId, `📝 지시 수신: "${parsed.args.slice(0, 100)}"\n다음 반복에 주입됩니다.`);
        break;
      case 'chat':
        await this.claudeRelay.handle({ ...msg, text: parsed.args });
        break;
      case 'claude':
      case 'codex':
        await this.claudeRelay.handle(
          { ...msg, text: parsed.args },
          parsed.command as AIBackend,
        );
        break;
    }
  }

  /** 활성 루프가 존재하는지 확인 */
  private async isLoopActive(): Promise<boolean> {
    const folders = await findActiveTaskFolders(this.stateDir);
    return folders.length > 0;
  }

  /** 상태 조회 → 메신저로 응답 */
  private async handleStatus(channelId: string): Promise<void> {
    const folders = await findActiveTaskFolders(this.stateDir);

    if (folders.length === 0) {
      await this.reply(channelId, '📊 현재 활성 태스크가 없습니다.');
      return;
    }

    for (const folder of folders) {
      const statePath = join(this.stateDir, 'state', folder, 'ralph-state.md');
      const notepadPath = join(this.stateDir, 'state', folder, 'notepad.md');
      const state = await parseRalphState(statePath);
      const notepad = await readNotepad(notepadPath);

      if (state) {
        const msg = formatStatusMessage(
          folder,
          state.phase,
          state.iteration,
          state.maxIterations,
          notepad,
        );
        await this.reply(channelId, msg);
      }
    }
  }

  /** ralph-state.md 필드를 직접 수정 */
  private async modifyRalphState(changes: Record<string, string>): Promise<void> {
    const folders = await findActiveTaskFolders(this.stateDir);
    // active가 true인 폴더가 없으면 가장 최근 폴더를 대상으로
    const target = folders[0];
    if (!target) return;

    const statePath = join(this.stateDir, 'state', target, 'ralph-state.md');
    try {
      let content = await readFile(statePath, 'utf-8');
      for (const [key, value] of Object.entries(changes)) {
        const regex = new RegExp(`(- ${key}:\\s*).+`);
        content = content.replace(regex, `$1${value}`);
      }
      await writeFile(statePath, content, 'utf-8');
    } catch {
      // 파일 없음 — 무시
    }
  }

  /** commands/ 에 명령 파일 작성 */
  private async writeCommand(command: Command, args: Record<string, string>): Promise<void> {
    const dir = join(this.messengerDir, 'commands');
    await ensureDir(dir);

    const file: CommandFile = {
      command,
      timestamp: new Date().toISOString(),
      args,
      status: 'pending',
    };

    const fileName = `${fileTimestamp()}_${command}.json`;
    await writeJsonAtomic(join(dir, fileName), file);
  }

  private async reply(channelId: string, text: string): Promise<void> {
    await this.adapter.sendNotification(channelId, {
      title: '',
      body: text,
      level: 'info',
      timestamp: new Date().toISOString(),
    });
  }

  /** 텍스트에서 명령 파싱 */
  private parseCommand(text: string): ParsedCommand | null {
    const trimmed = text.trim();

    // 슬래시 명령
    const slashMatch = trimmed.match(/^\/(start|stop|resume|cancel|status|instruct|chat|claude|codex)\s*(.*)/i);
    if (slashMatch) {
      return { command: slashMatch[1].toLowerCase() as Command, args: slashMatch[2].trim() };
    }

    // 한국어 키워드
    const koMap: [RegExp, Command][] = [
      [/^시작\s+(.+)/i, 'start'],
      [/^중지$/i, 'stop'],
      [/^재개$/i, 'resume'],
      [/^취소$/i, 'cancel'],
      [/^상태$/i, 'status'],
    ];

    for (const [regex, cmd] of koMap) {
      const m = trimmed.match(regex);
      if (m) {
        return { command: cmd, args: m[1]?.trim() ?? '' };
      }
    }

    return null;
  }
}
