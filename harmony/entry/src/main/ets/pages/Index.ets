import { NearbyDevice, SelectedFile, TransferDirection, TransferRecord, TransferStatus } from '../common/Models';
import { AppSettings } from '../common/Settings';
import { FileUtil } from '../util/FileUtil';
import {
  IncomingRequestInfo, LocalSendService
} from '../service/LocalSendService';

function formatSize(bytes: number): string {
  if (bytes < 1024) {
    return bytes.toString() + ' B';
  }
  if (bytes < 1024 * 1024) {
    return (bytes / 1024).toFixed(1) + ' KB';
  }
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function formatTime(timestamp: number): string {
  return new Date(timestamp).toISOString().substring(11, 19);
}

function statusText(status: TransferStatus): string {
  if (status === TransferStatus.DONE) {
    return '完成';
  }
  if (status === TransferStatus.FAILED) {
    return '失败';
  }
  if (status === TransferStatus.RUNNING) {
    return '传输中';
  }
  if (status === TransferStatus.DECLINED) {
    return '已拒绝';
  }
  return '等待中';
}

@Entry
@Component
struct Index {
  @State devices: NearbyDevice[] = [];
  @State records: TransferRecord[] = [];
  @State selected: SelectedFile[] = [];
  @State statusTextLine: string = '正在启动…';
  @State errorMessage: string = '';
  @State aliasInput: string = 'Harmony Device';
  @State portInput: string = '53317';
  @State pinInput: string = '';
  @State targetPinInput: string = '';
  @State autoAccept: boolean = true;
  @State webSend: boolean = false;
  @State localIp: string = '';
  @State shareLink: string = '';
  @State currentTab: number = 0;
  @State showIncoming: boolean = false;
  @State incomingId: string = '';
  @State incomingAlias: string = '';
  @State incomingDesc: string = '';
  @State busy: boolean = false;

  private service: LocalSendService = LocalSendService.shared();
  private uiTimer: number = -1;

  aboutToAppear(): void {
    this.service.start().then(async () => {
      this.aliasInput = this.service.settings.alias;
      this.portInput = this.service.settings.port.toString();
      this.pinInput = this.service.settings.pin;
      this.autoAccept = this.service.settings.autoAccept;
      this.webSend = this.service.settings.webSend;
      this.localIp = await this.service.localIp();
    }).catch((e: Error) => {
      this.statusTextLine = '启动失败';
      this.errorMessage = e.message;
    });
    this.uiTimer = setInterval(() => {
      this.syncState();
    }, 500);
  }

  aboutToDisappear(): void {
    if (this.uiTimer >= 0) {
      clearInterval(this.uiTimer);
      this.uiTimer = -1;
    }
    this.service.stop();
  }

  private syncState(): void {
    this.devices = this.service.listDevices();
    this.records = this.service.listRecords();
    this.statusTextLine = this.service.statusMessage;
    let error: string = this.service.consumeError();
    if (error.length > 0) {
      this.errorMessage = error;
    }
    if (!this.showIncoming) {
      let incoming: IncomingRequestInfo | null = this.service.drainIncoming();
      if (incoming !== null) {
        let info: IncomingRequestInfo = incoming as IncomingRequestInfo;
        this.incomingId = info.id;
        this.incomingAlias = info.alias;
        this.incomingDesc = info.fileCount.toString() + ' 个文件 · ' + formatSize(info.totalSize);
        this.showIncoming = true;
      }
    }
  }

  private async doPick(): Promise<void> {
    try {
      this.busy = true;
      let files: SelectedFile[] = await this.service.pickFiles();
      this.selected = files;
      this.shareLink = '';
      this.errorMessage = '';
    } catch (e) {
      this.errorMessage = '选择文件失败';
    } finally {
      this.busy = false;
    }
  }

  private doSend(device: NearbyDevice): void {
    if (this.selected.length === 0) {
      this.errorMessage = '请先选择要发送的文件';
      return;
    }
    this.errorMessage = '';
    this.statusTextLine = '正在发送给 ' + device.info.alias + '…';
    this.service.sendFiles(device, this.selected, this.targetPinInput).then(() => {
      this.statusTextLine = '发送流程结束';
    }).catch((e: Error) => {
      this.errorMessage = e.message;
    });
  }

  private async doSaveSettings(): Promise<void> {
    let port: number = Number.parseInt(this.portInput);
    if (isNaN(port) || port <= 0 || port > 65535) {
      this.errorMessage = '端口必须是 1-65535';
      return;
    }
    let settings: AppSettings = this.service.settings;
    settings.alias = this.aliasInput;
    settings.port = port;
    settings.pin = this.pinInput;
    settings.autoAccept = this.autoAccept;
    settings.webSend = this.webSend;
    await this.service.updateSettings(settings);
    this.errorMessage = '已保存；端口与加密设置需重启应用后生效';
  }

  private async doShareLink(): Promise<void> {
    if (this.selected.length === 0) {
      this.errorMessage = '请先选择要分享的文件';
      return;
    }
    try {
      this.shareLink = await this.service.shareViaLink(this.selected);
    } catch (e) {
      this.errorMessage = '生成分享链接失败';
    }
  }

  @Builder
  deviceItem(device: NearbyDevice) {
    Row() {
      Column() {
        Text(device.info.alias)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#182230')
        Text(device.info.deviceModel + ' · ' + device.ip + ':' + device.port.toString() +
          ' · ' + device.protocol.toUpperCase())
          .fontSize(12)
          .fontColor('#6B7785')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button('发送')
        .fontSize(14)
        .height(34)
        .backgroundColor('#2F6FED')
        .onClick(() => {
          this.doSend(device);
        })
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }

  build() {
    Stack() {
      Column() {
        Column() {
          Text('LocalSend · 鸿蒙版')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#182230')
          Text(this.service.settings.alias + ' · ' + this.localIp + ':' + this.portInput + ' · HTTP')
            .fontSize(12)
            .fontColor('#6B7785')
            .margin({ top: 6 })
          Text(this.statusTextLine)
            .fontSize(12)
            .fontColor('#2F6FED')
            .margin({ top: 6 })
          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(12)
              .fontColor('#D64545')
              .margin({ top: 6 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 18, bottom: 14 })

        Tabs({ index: this.currentTab }) {
          TabContent() {
            Column() {
              Row() {
                Button(this.busy ? '选择中…' : '选择文件')
                  .fontSize(14)
                  .height(38)
                  .backgroundColor('#2F6FED')
                  .onClick(() => {
                    this.doPick();
                  })
                Button('刷新设备')
                  .fontSize(14)
                  .height(38)
                  .backgroundColor('#E8EEF9')
                  .fontColor('#2F6FED')
                  .margin({ left: 10 })
                  .onClick(() => {
                    this.service.refresh();
                  })
              }
              .width('100%')
              .margin({ bottom: 10 })

              Text(this.selected.length === 0 ? '尚未选择文件' : '已选择 ' + this.selected.length.toString() + ' 个文件')
                .fontSize(13)
                .fontColor('#6B7785')
                .width('100%')
                .margin({ bottom: 8 })

              Row() {
                Text('发送 PIN（对方开启时需要）')
                  .fontSize(13)
                  .fontColor('#6B7785')
                TextInput({ placeholder: '可选' })
                  .fontSize(13)
                  .height(36)
                  .layoutWeight(1)
                  .margin({ left: 10 })
                  .backgroundColor('#FFFFFF')
                  .onChange((value: string) => {
                    this.targetPinInput = value;
                  })
              }
              .width('100%')
              .margin({ bottom: 12 })

              Text('附近设备 (' + this.devices.length.toString() + ')')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .width('100%')
                .margin({ bottom: 8 })

              if (this.devices.length === 0) {
                Text('暂无设备。请确保对方也打开 LocalSend 并处于同一局域网。')
                  .fontSize(13)
                  .fontColor('#8A94A0')
                  .width('100%')
                  .padding(16)
                  .backgroundColor('#FFFFFF')
                  .borderRadius(12)
              } else {
                List({ space: 8 }) {
                  ForEach(this.devices, (device: NearbyDevice) => {
                    ListItem() {
                      this.deviceItem(device)
                    }
                  }, (device: NearbyDevice) => device.info.fingerprint + '@' + device.ip)
                }
                .width('100%')
                .layoutWeight(1)
              }
            }
            .width('100%')
            .height('100%')
            .padding({ left: 16, right: 16, top: 12 })
          }
          .tabBar('发送')

          TabContent() {
            Column() {
              Text('传输记录')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .width('100%')
                .margin({ bottom: 10 })
              Text('接收目录: ' + FileUtil.receiveDir())
                .fontSize(12)
                .fontColor('#6B7785')
                .width('100%')
                .margin({ bottom: 10 })
              if (this.records.length === 0) {
                Text('暂无记录')
                  .fontSize(13)
                  .fontColor('#8A94A0')
              } else {
                List({ space: 8 }) {
                  ForEach(this.records, (record: TransferRecord) => {
                    ListItem() {
                      Row() {
                        Column() {
                          Text(record.fileName)
                            .fontSize(15)
                            .fontColor('#182230')
                          Text((record.direction === TransferDirection.SEND ? '发送至 ' : '接收自 ') +
                            record.peer + ' · ' + formatSize(record.size) + ' · ' + formatTime(record.timestamp))
                            .fontSize(12)
                            .fontColor('#6B7785')
                            .margin({ top: 4 })
                          if (record.detail.length > 0) {
                            Text(record.detail)
                              .fontSize(11)
                              .fontColor('#8A94A0')
                              .margin({ top: 2 })
                          }
                        }
                        .alignItems(HorizontalAlign.Start)
                        .layoutWeight(1)
                        Text(statusText(record.status))
                          .fontSize(13)
                          .fontColor(record.status === TransferStatus.FAILED ? '#D64545' : '#2F8F5B')
                      }
                      .width('100%')
                      .padding(14)
                      .backgroundColor('#FFFFFF')
                      .borderRadius(12)
                    }
                  }, (record: TransferRecord) => record.id)
                }
                .width('100%')
                .layoutWeight(1)
              }
            }
            .width('100%')
            .height('100%')
            .padding(16)
          }
          .tabBar('记录')

          TabContent() {
            Scroll() {
              Column() {
                Text('设置')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .width('100%')
                  .margin({ bottom: 12 })

                Text('设备别名')
                  .fontSize(13)
                  .fontColor('#6B7785')
                  .width('100%')
                TextInput({ text: this.aliasInput, placeholder: '设备别名' })
                  .height(40)
                  .backgroundColor('#FFFFFF')
                  .margin({ bottom: 12 })
                  .onChange((value: string) => {
                    this.aliasInput = value;
                  })

                Text('端口（默认 53317）')
                  .fontSize(13)
                  .fontColor('#6B7785')
                  .width('100%')
                TextInput({ text: this.portInput, placeholder: '53317' })
                  .height(40)
                  .type(InputType.Number)
                  .backgroundColor('#FFFFFF')
                  .margin({ bottom: 12 })
                  .onChange((value: string) => {
                    this.portInput = value;
                  })

                Text('接收 PIN（留空表示不需要）')
                  .fontSize(13)
                  .fontColor('#6B7785')
                  .width('100%')
                TextInput({ text: this.pinInput, placeholder: '可选' })
                  .height(40)
                  .backgroundColor('#FFFFFF')
                  .margin({ bottom: 12 })
                  .onChange((value: string) => {
                    this.pinInput = value;
                  })

                Row() {
                  Text('自动接收文件')
                    .fontSize(14)
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.autoAccept })
                    .onChange((isOn: boolean) => {
                      this.autoAccept = isOn;
                    })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })

                Row() {
                  Text('启用链接分享（反向下载）')
                    .fontSize(14)
                    .layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.webSend })
                    .onChange((isOn: boolean) => {
                      this.webSend = isOn;
                    })
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })

                Button('保存设置')
                  .width('100%')
                  .height(40)
                  .backgroundColor('#2F6FED')
                  .margin({ top: 10 })
                  .onClick(() => {
                    this.doSaveSettings();
                  })

                Button('生成分享链接')
                  .width('100%')
                  .height(40)
                  .backgroundColor('#E8EEF9')
                  .fontColor('#2F6FED')
                  .margin({ top: 10 })
                  .onClick(() => {
                    this.doShareLink();
                  })

                if (this.shareLink.length > 0) {
                  Text(this.shareLink)
                    .fontSize(12)
                    .fontColor('#2F6FED')
                    .width('100%')
                    .padding(10)
                    .backgroundColor('#FFFFFF')
                    .borderRadius(8)
                    .margin({ top: 8 })
                }

                Text('说明：本版本使用 HTTP 明文传输，与官方客户端互通时请在双方设置中关闭「加密」。' +
                  'HTTPS / 双向证书认证需要 TLS 服务端证书，将在后续版本实现。')
                  .fontSize(12)
                  .fontColor('#8A94A0')
                  .width('100%')
                  .margin({ top: 20 })
              }
              .width('100%')
              .padding(16)
            }
            .width('100%')
            .height('100%')
          }
          .tabBar('设置')
        }
        .barHeight(44)
        .width('100%')
        .layoutWeight(1)
        .onChange((index: number) => {
          this.currentTab = index;
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F4F6F9')

      if (this.showIncoming) {
        Column() {
          Column() {
            Text('收到传输请求')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#182230')
            Text(this.incomingAlias)
              .fontSize(14)
              .fontColor('#2F6FED')
              .margin({ top: 10 })
            Text(this.incomingDesc)
              .fontSize(13)
              .fontColor('#6B7785')
              .margin({ top: 6 })
            Row() {
              Button('拒绝')
                .layoutWeight(1)
                .backgroundColor('#EEF1F5')
                .fontColor('#6B7785')
                .onClick(() => {
                  this.service.respondToIncoming(this.incomingId, false);
                  this.showIncoming = false;
                })
              Button('接受')
                .layoutWeight(1)
                .backgroundColor('#2F6FED')
                .margin({ left: 10 })
                .onClick(() => {
                  this.service.respondToIncoming(this.incomingId, true);
                  this.showIncoming = false;
                })
            }
            .width('100%')
            .margin({ top: 20 })
          }
          .width('86%')
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#99000000')
      }
    }
    .width('100%')
    .height('100%')
  }
}
