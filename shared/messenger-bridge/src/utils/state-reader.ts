/**
 * ralph-state.md / notepad.md 파서
 * @author JunyoungJung
 * @date 2026-04-02
 */

import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';

export interface RalphState {
  active: boolean;
  iteration: number;
  maxIterations: number;
  phase: string;
  taskDescription: string;
  completionLevel: number;
  startedAt: string;
}

/** ralph-state.md를 파싱하여 구조체로 반환 */
export async function parseRalphState(filePath: string): Promise<RalphState | null> {
  try {
    const content = await readFile(filePath, 'utf-8');
    return {
      active: extractBool(content, 'active'),
      iteration: extractInt(content, 'iteration'),
      maxIterations: extractInt(content, 'maxIterations'),
      phase: extractStr(content, 'phase'),
      taskDescription: extractStr(content, 'taskDescription'),
      completionLevel: extractInt(content, 'completionLevel'),
      startedAt: extractStr(content, 'startedAt'),
    };
  } catch {
    return null;
  }
}

/** notepad.md 전체 내용을 문자열로 반환 */
export async function readNotepad(filePath: string): Promise<string | null> {
  try {
    return await readFile(filePath, 'utf-8');
  } catch {
    return null;
  }
}

/** 프로젝트 state 디렉터리에서 활성 태스크 폴더 목록 반환 */
export async function findActiveTaskFolders(stateDir: string): Promise<string[]> {
  const active: string[] = [];
  try {
    const folders = await readdir(join(stateDir, 'state'));
    for (const folder of folders) {
      const statePath = join(stateDir, 'state', folder, 'ralph-state.md');
      const state = await parseRalphState(statePath);
      if (state?.active) {
        active.push(folder);
      }
    }
  } catch {
    // state 디렉터리 없음
  }
  return active;
}

// ── 내부 헬퍼 ──

function extractStr(content: string, key: string): string {
  const match = content.match(new RegExp(`- ${key}:\\s*(.+)`));
  return match?.[1]?.trim() ?? '';
}

function extractInt(content: string, key: string): number {
  return parseInt(extractStr(content, key), 10) || 0;
}

function extractBool(content: string, key: string): boolean {
  return extractStr(content, key) === 'true';
}
