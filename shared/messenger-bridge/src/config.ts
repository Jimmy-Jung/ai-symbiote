/**
 * 메신저 브릿지 설정 로더
 * @author JunyoungJung
 * @date 2026-04-02
 */

import { readJson, writeJsonAtomic, ensureDir } from './utils/file-protocol.js';
import { join } from 'node:path';
import type { Platform } from './adapters/types.js';

export interface SlackConfig {
  botToken: string;
  appToken: string;
  signingSecret: string;
  channelId: string;
}

export interface DiscordConfig {
  token: string;
  channelId: string;
}

export interface TelegramConfig {
  token: string;
  chatId: string;
  /** 허용된 Telegram 사용자 ID 목록 (비어있으면 모든 사용자 허용) */
  allowedUserIds?: string[];
}

export type PermissionLevel = 'readonly' | 'safe' | 'full';

export interface SecurityConfig {
  /** 권한 레벨: readonly(읽기만), safe(Bash차단, 기본), full(제한없음) */
  permissionLevel: PermissionLevel;
  /** 허용 도구 커스텀 목록 (permissionLevel 대신 직접 지정) */
  allowedTools?: string[];
  /** 차단 도구 커스텀 목록 */
  disallowedTools?: string[];
}

export interface MessengerPreferences {
  notifyOnPhaseChange: boolean;
  notifyOnIterationComplete: boolean;
  approvalTimeoutSeconds: number;
  language: string;
}

export interface MessengerConfig {
  version: string;
  enabled: boolean;
  platform: Platform;
  slack?: SlackConfig;
  discord?: DiscordConfig;
  telegram?: TelegramConfig;
  preferences: MessengerPreferences;
  /** AI CLI 릴레이용 프로젝트 디렉터리 */
  projectDir?: string;
  /** 기본 AI 백엔드: 'claude' | 'codex' (기본값: claude) */
  defaultBackend?: 'claude' | 'codex';
  /** 보안 설정 (기본: safe 모드) */
  security?: SecurityConfig;
}

const DEFAULT_PREFERENCES: MessengerPreferences = {
  notifyOnPhaseChange: true,
  notifyOnIterationComplete: false,
  approvalTimeoutSeconds: 1800,
  language: 'ko',
};

/** messenger 디렉터리 경로 */
export function messengerDir(stateDir: string): string {
  return join(stateDir, 'messenger');
}

/** config.json 전체 경로 */
export function configPath(stateDir: string): string {
  return join(messengerDir(stateDir), 'config.json');
}

/** 설정 로드 (없으면 null) */
export async function loadConfig(stateDir: string): Promise<MessengerConfig | null> {
  return readJson<MessengerConfig>(configPath(stateDir));
}

/** 설정 저장 */
export async function saveConfig(stateDir: string, config: MessengerConfig): Promise<void> {
  const dir = messengerDir(stateDir);
  await ensureDir(dir);
  await ensureDir(join(dir, 'notifications'));
  await ensureDir(join(dir, 'approvals'));
  await ensureDir(join(dir, 'commands'));
  await writeJsonAtomic(configPath(stateDir), config);
}

/** 기본 설정 생성 */
export function createDefaultConfig(platform: Platform): MessengerConfig {
  return {
    version: '1.0.0',
    enabled: true,
    platform,
    preferences: { ...DEFAULT_PREFERENCES },
  };
}
