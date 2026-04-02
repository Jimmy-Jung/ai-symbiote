/**
 * 원자적 JSON 파일 읽기/쓰기 유틸리티
 * @author JunyoungJung
 * @date 2026-04-02
 *
 * tmp 파일에 쓴 후 rename하여 partial read를 방지한다.
 */

import { writeFile, readFile, rename, readdir, stat, mkdir } from 'node:fs/promises';
import { join, basename } from 'node:path';
import { randomBytes } from 'node:crypto';

/** 원자적 JSON 쓰기: tmp에 쓰고 rename */
export async function writeJsonAtomic<T>(filePath: string, data: T): Promise<void> {
  const tmpPath = `${filePath}.${randomBytes(4).toString('hex')}.tmp`;
  const content = JSON.stringify(data, null, 2) + '\n';
  await writeFile(tmpPath, content, 'utf-8');
  await rename(tmpPath, filePath);
}

/** JSON 파일 읽기 (없으면 null) */
export async function readJson<T>(filePath: string): Promise<T | null> {
  try {
    const content = await readFile(filePath, 'utf-8');
    return JSON.parse(content) as T;
  } catch {
    return null;
  }
}

/** 디렉터리 내 특정 패턴의 JSON 파일 목록 (정렬됨) */
export async function listJsonFiles(dir: string, suffix?: string): Promise<string[]> {
  try {
    const files = await readdir(dir);
    return files
      .filter(f => f.endsWith('.json') && (!suffix || f.includes(suffix)))
      .sort()
      .map(f => join(dir, f));
  } catch {
    return [];
  }
}

/** 파일을 .sent/.done/.expired로 rename */
export async function markFile(filePath: string, tag: 'sent' | 'done' | 'expired'): Promise<void> {
  const newPath = filePath.replace(/\.json$/, `.${tag}`);
  await rename(filePath, newPath);
}

/** 디렉터리가 없으면 생성 */
export async function ensureDir(dir: string): Promise<void> {
  try {
    await mkdir(dir, { recursive: true });
  } catch {
    // 이미 존재
  }
}

/** ISO8601 타임스탬프 생성 (파일명 안전) */
export function fileTimestamp(): string {
  return new Date().toISOString().replace(/[:.]/g, '-');
}

/** 파일 존재 여부 확인 */
export async function fileExists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

/** 파일 나이 (ms) 계산 */
export async function fileAgeMs(filePath: string): Promise<number> {
  const s = await stat(filePath);
  return Date.now() - s.mtimeMs;
}
