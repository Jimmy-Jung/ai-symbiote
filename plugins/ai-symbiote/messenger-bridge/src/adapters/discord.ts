/**
 * Discord 어댑터 — discord.js 기반
 * @author JunyoungJung
 * @date 2026-04-02
 */

import {
  Client,
  GatewayIntentBits,
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  EmbedBuilder,
  type TextChannel,
  type ButtonInteraction,
  type Message,
} from 'discord.js';
import type {
  MessengerAdapter,
  PlatformConfig,
  NotificationMessage,
  ApprovalRequest,
  ActionHandler,
  MessageHandler,
  UserAction,
  UserMessage,
} from './types.js';

const LEVEL_COLOR: Record<string, number> = {
  info: 0x2196f3,
  warn: 0xff9800,
  error: 0xf44336,
  success: 0x4caf50,
};

export class DiscordAdapter implements MessengerAdapter {
  readonly platform = 'discord' as const;
  private client: Client | null = null;
  private connected = false;
  private actionHandler: ActionHandler | null = null;
  private messageHandler: MessageHandler | null = null;
  private pendingModify: { requestId: string; userId: string } | null = null;
  private configChannelId = '';

  async connect(config: PlatformConfig): Promise<void> {
    this.configChannelId = config.channelId;
    this.client = new Client({
      intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
      ],
    });

    // 버튼 인터랙션
    this.client.on('interactionCreate', async (interaction) => {
      if (!interaction.isButton()) return;
      const btnInteraction = interaction as ButtonInteraction;
      if (!this.actionHandler) return;

      const [actionId, requestId] = btnInteraction.customId.split(':');
      if (!actionId || !requestId) return;

      const action: UserAction = {
        platform: 'discord',
        userId: btnInteraction.user.id,
        channelId: btnInteraction.channelId,
        messageId: btnInteraction.message.id,
        actionId,
        requestId,
      };

      if (actionId === 'modify') {
        this.pendingModify = { requestId, userId: btnInteraction.user.id };
        await btnInteraction.reply({ content: '수정 지시를 입력하세요:', ephemeral: true });
      } else {
        await this.actionHandler(action);
        const label = actionId === 'approve' ? '승인' : '거부';
        await btnInteraction.reply({ content: `${label}되었습니다.`, ephemeral: true });
      }
    });

    // 텍스트 메시지
    this.client.on('messageCreate', async (message: Message) => {
      if (message.author.bot) return;

      // pending modify 처리
      if (
        this.pendingModify &&
        message.author.id === this.pendingModify.userId &&
        this.actionHandler
      ) {
        const action: UserAction = {
          platform: 'discord',
          userId: message.author.id,
          channelId: message.channelId,
          messageId: message.id,
          actionId: 'modify',
          value: message.content,
          requestId: this.pendingModify.requestId,
        };
        await this.actionHandler(action);
        this.pendingModify = null;
        await message.reply('수정 지시가 전달되었습니다.');
        return;
      }

      // 일반 메시지 → Stage 3
      if (this.messageHandler && message.channelId === this.configChannelId) {
        const msg: UserMessage = {
          platform: 'discord',
          userId: message.author.id,
          channelId: message.channelId,
          text: message.content,
          timestamp: new Date().toISOString(),
        };
        await this.messageHandler(msg);
      }
    });

    await this.client.login(config.token);
    this.connected = true;
  }

  async disconnect(): Promise<void> {
    if (this.client) {
      await this.client.destroy();
      this.connected = false;
    }
  }

  async sendNotification(channelId: string, msg: NotificationMessage): Promise<string> {
    const channel = await this.getChannel(channelId);
    if (!msg.title) {
      const sent = await channel.send(msg.body);
      return sent.id;
    }

    const embed = new EmbedBuilder()
      .setTitle(msg.title)
      .setDescription(msg.body)
      .setColor(LEVEL_COLOR[msg.level] ?? LEVEL_COLOR.info)
      .setTimestamp();

    if (msg.fields) {
      for (const [name, value] of Object.entries(msg.fields)) {
        embed.addFields({ name, value, inline: true });
      }
    }

    const sent = await channel.send({ embeds: [embed] });
    return sent.id;
  }

  async sendApprovalRequest(channelId: string, req: ApprovalRequest): Promise<string> {
    const channel = await this.getChannel(channelId);

    const embed = new EmbedBuilder()
      .setTitle(`⚠️ ${req.title}`)
      .setDescription(req.context)
      .setColor(LEVEL_COLOR.warn)
      .addFields(
        { name: '단계', value: req.phase, inline: true },
        { name: '반복', value: `${req.iteration}/${req.maxIterations}`, inline: true },
        { name: '타임아웃', value: `${Math.round(req.timeoutSeconds / 60)}분`, inline: true },
      )
      .setTimestamp();

    if (req.taskDescription) {
      embed.addFields({ name: '제안', value: req.taskDescription });
    }

    const styleMap: Record<string, ButtonStyle> = {
      primary: ButtonStyle.Primary,
      danger: ButtonStyle.Danger,
    };

    const buttons = req.options.map(opt =>
      new ButtonBuilder()
        .setCustomId(`${opt.id}:${req.id}`)
        .setLabel(opt.label)
        .setStyle(styleMap[opt.style ?? ''] ?? ButtonStyle.Secondary),
    );

    const row = new ActionRowBuilder<ButtonBuilder>().addComponents(buttons);
    const sent = await channel.send({ embeds: [embed], components: [row] });
    return sent.id;
  }

  async updateMessage(channelId: string, msgId: string, msg: NotificationMessage): Promise<void> {
    const channel = await this.getChannel(channelId);
    const message = await channel.messages.fetch(msgId);
    const embed = new EmbedBuilder()
      .setTitle(msg.title)
      .setDescription(msg.body)
      .setColor(LEVEL_COLOR[msg.level] ?? LEVEL_COLOR.info)
      .setTimestamp();
    await message.edit({ embeds: [embed], components: [] });
  }

  onAction(handler: ActionHandler): void {
    this.actionHandler = handler;
  }

  onMessage(handler: MessageHandler): void {
    this.messageHandler = handler;
  }

  isConnected(): boolean {
    return this.connected;
  }

  private async getChannel(channelId: string): Promise<TextChannel> {
    if (!this.client) throw new Error('Client not connected');
    const channel = await this.client.channels.fetch(channelId);
    if (!channel?.isTextBased()) throw new Error(`채널을 찾을 수 없습니다: ${channelId}`);
    return channel as TextChannel;
  }
}
