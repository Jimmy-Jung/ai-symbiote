/**
 * Stage 2: 승인/거부 핸들러
 * @author JunyoungJung
 * @date 2026-04-02
 *
 * approvals/{id}_request.json을 메신저로 전송하고,
 * 사용자 응답을 {id}_response.json으로 기록한다.
 */

import type { MessengerAdapter, ApprovalRequest, UserAction } from '../adapters/types.js';
import type { MessengerConfig } from '../config.js';
import { writeJsonAtomic, fileExists } from '../utils/file-protocol.js';
import { dirname, join } from 'node:path';

interface ApprovalRequestFile {
  id: string;
  timestamp: string;
  taskFolder: string;
  type: string;
  question: string;
  context: {
    iteration: number;
    maxIterations: number;
    phase: string;
    recentErrors?: string[];
    attemptedApproaches?: string[];
    suggestedAction?: string;
  };
  options: string[];
  timeoutSeconds: number;
  status: string;
}

interface ApprovalResponseFile {
  id: string;
  timestamp: string;
  decision: string;
  comment: string;
  respondedBy: string;
}

export class ApprovalHandler {
  private pendingTimeouts = new Map<string, ReturnType<typeof setTimeout>>();

  constructor(
    private adapter: MessengerAdapter,
    private config: MessengerConfig,
    private messengerDir: string,
  ) {}

  /** 새 승인 요청 파일을 메신저로 전송 */
  async handleRequest(filePath: string, data: unknown): Promise<void> {
    const req = data as ApprovalRequestFile;

    const approvalReq: ApprovalRequest = {
      id: req.id,
      title: `승인 요청: ${req.type}`,
      context: req.question,
      taskDescription: req.context.suggestedAction ?? '',
      iteration: req.context.iteration,
      maxIterations: req.context.maxIterations,
      phase: req.context.phase,
      options: [
        { id: 'approve', label: '승인', style: 'primary' },
        { id: 'reject', label: '거부', style: 'danger' },
        { id: 'modify', label: '수정 지시' },
      ],
      timeoutSeconds: req.timeoutSeconds,
    };

    const channelId = this.getChannelId();
    await this.adapter.sendApprovalRequest(channelId, approvalReq);

    // 타임아웃 설정
    const timeout = setTimeout(async () => {
      await this.writeTimeoutResponse(req.id);
      this.pendingTimeouts.delete(req.id);
    }, req.timeoutSeconds * 1000);

    this.pendingTimeouts.set(req.id, timeout);
  }

  /** 사용자 액션(버튼 클릭)을 응답 파일로 기록 */
  async handleUserAction(action: UserAction): Promise<void> {
    const timeout = this.pendingTimeouts.get(action.requestId);
    if (timeout) {
      clearTimeout(timeout);
      this.pendingTimeouts.delete(action.requestId);
    }

    const response: ApprovalResponseFile = {
      id: action.requestId,
      timestamp: new Date().toISOString(),
      decision: action.actionId,
      comment: action.value ?? '',
      respondedBy: action.userId,
    };

    const responsePath = join(
      this.messengerDir,
      'approvals',
      `${action.requestId}_response.json`,
    );
    await writeJsonAtomic(responsePath, response);
  }

  /** 타임아웃 시 자동 응답 작성 */
  private async writeTimeoutResponse(requestId: string): Promise<void> {
    const responsePath = join(this.messengerDir, 'approvals', `${requestId}_response.json`);
    if (await fileExists(responsePath)) return;

    const response: ApprovalResponseFile = {
      id: requestId,
      timestamp: new Date().toISOString(),
      decision: 'timeout',
      comment: '승인 요청 시간 초과',
      respondedBy: 'system',
    };
    await writeJsonAtomic(responsePath, response);
  }

  /** 정리: 모든 타임아웃 취소 */
  cleanup(): void {
    for (const timeout of this.pendingTimeouts.values()) {
      clearTimeout(timeout);
    }
    this.pendingTimeouts.clear();
  }

  private getChannelId(): string {
    const p = this.config.platform;
    if (p === 'slack') return this.config.slack!.channelId;
    if (p === 'discord') return this.config.discord!.channelId;
    return this.config.telegram!.chatId;
  }
}
