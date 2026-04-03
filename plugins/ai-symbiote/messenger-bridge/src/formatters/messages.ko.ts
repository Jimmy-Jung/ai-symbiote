/**
 * 한국어 메시지 템플릿
 * @author JunyoungJung
 * @date 2026-04-02
 */

import type { NotificationMessage, NotificationLevel } from '../adapters/types.js';

const LEVEL_EMOJI: Record<NotificationLevel, string> = {
  info: 'ℹ️',
  warn: '⚠️',
  error: '🚨',
  success: '✅',
};

interface NotificationEventData {
  event: string;
  taskFolder: string;
  data: {
    iteration?: number;
    maxIterations?: number;
    phase?: string;
    summary?: string;
    taskDescription?: string;
    errorDetail?: string;
    escalationReason?: string;
  };
}

export function formatNotification(raw: NotificationEventData): NotificationMessage {
  const { event, taskFolder, data } = raw;

  switch (event) {
    case 'loop_start':
      return {
        title: '루프 시작',
        body: `작업: ${data.taskDescription ?? taskFolder}\n최대 반복: ${data.maxIterations ?? '?'}회`,
        level: 'info',
        fields: { '태스크': taskFolder },
        timestamp: new Date().toISOString(),
      };

    case 'phase_change':
      return {
        title: `단계 전환 → ${data.phase}`,
        body: `반복 ${data.iteration ?? '?'}/${data.maxIterations ?? '?'}\n${data.summary ?? ''}`,
        level: 'info',
        fields: { '태스크': taskFolder, '단계': data.phase ?? '' },
        timestamp: new Date().toISOString(),
      };

    case 'escalation':
      return {
        title: '에스컬레이션 — 사용자 개입 필요',
        body: `사유: ${data.escalationReason ?? '알 수 없음'}\n현재: ${data.phase} (반복 ${data.iteration}/${data.maxIterations})`,
        level: 'warn',
        fields: { '태스크': taskFolder },
        timestamp: new Date().toISOString(),
      };

    case 'error':
      return {
        title: '오류 발생',
        body: data.errorDetail ?? '알 수 없는 오류',
        level: 'error',
        fields: {
          '태스크': taskFolder,
          '반복': `${data.iteration ?? '?'}/${data.maxIterations ?? '?'}`,
        },
        timestamp: new Date().toISOString(),
      };

    case 'loop_complete':
      return {
        title: '작업 완료',
        body: `작업: ${data.taskDescription ?? taskFolder}\n총 반복: ${data.iteration ?? '?'}회\n${data.summary ?? ''}`,
        level: 'success',
        fields: { '태스크': taskFolder },
        timestamp: new Date().toISOString(),
      };

    default:
      return {
        title: event,
        body: JSON.stringify(data, null, 2),
        level: 'info',
        timestamp: new Date().toISOString(),
      };
  }
}

/** 알림 메시지를 플레인 텍스트로 변환 (플랫폼 공통) */
export function toPlainText(msg: NotificationMessage): string {
  const emoji = LEVEL_EMOJI[msg.level];
  let text = `${emoji} *${msg.title}*\n${msg.body}`;
  if (msg.fields) {
    const fieldLines = Object.entries(msg.fields)
      .map(([k, v]) => `• ${k}: ${v}`)
      .join('\n');
    text += `\n\n${fieldLines}`;
  }
  return text;
}

/** 상태 요약 메시지 생성 */
export function formatStatusMessage(
  taskFolder: string,
  phase: string,
  iteration: number,
  maxIterations: number,
  notepadSummary: string | null,
): string {
  let msg = `📊 *현재 상태*\n`;
  msg += `• 태스크: ${taskFolder}\n`;
  msg += `• 단계: ${phase}\n`;
  msg += `• 반복: ${iteration}/${maxIterations}\n`;
  if (notepadSummary) {
    const trimmed = notepadSummary.slice(0, 500);
    msg += `\n📝 *노트패드 요약*\n${trimmed}`;
  }
  return msg;
}
