# Sing Geosite 规则构建仓库

这个仓库用于每天自动构建一组固定输出规则，路由器只需要下载成品，不再承担反编译、合并和编译压力。

## 输入

- `lists/direct.txt`：直连 geosite 规则标签，每行一个。
- `lists/proxy.txt`：代理 geosite 规则标签，每行一个。

规则名可以写成 `google`，也可以写成 `geosite-google.srs`。空行和 `#` 注释会被忽略。

## 输出

构建完成后，`dist/` 会生成三组文件：

- sing-box 二进制规则集
  - `direct-geosite.srs`
  - `proxy-geosite.srs`
- mosdns 规则集
  - `direct-geosite.txt`
  - `proxy-geosite.txt`
- JSON 规则集
  - `direct-geosite.json`
  - `proxy-geosite.json`

辅助文件：

- `manifest.json`：构建时间、规则数量、输出文件清单。
- `scan-preview.txt`：找到、缺失、冲突的规则预览。
- `sing-box-route.json`：sing-box route 片段。
- `mosdns-domain-set.yaml`：mosdns domain_set 片段。

## 每日自动构建

GitHub Actions 会每天北京时间 07:30 自动运行：

```yaml
schedule:
  - cron: "30 23 * * *"
```

这里的时间是 UTC，等于北京时间第二天 07:30。

## 手动构建

本地需要安装：

- `sing-box`
- `curl`
- `jq`
- `unzip`

运行：

```bash
./scripts/build.sh
```

默认上游是：

```text
https://github.com/SagerNet/sing-geosite/tree/rule-set
```

也可以临时指定：

```bash
SOURCE_URL=https://github.com/SagerNet/sing-geosite/tree/rule-set ./scripts/build.sh
```

## 路由器侧使用建议

OpenWrt 插件后续可以只下载 `dist/` 内成品：

- `/etc/sing-box/rule-set/direct-geosite.srs`
- `/etc/sing-box/rule-set/proxy-geosite.srs`
- `/etc/mosdns/rule/direct-geosite.txt`
- `/etc/mosdns/rule/proxy-geosite.txt`

插件不需要修改 sing-box 主配置，也不需要修改 inbound、outbound、节点或 mosdns 主逻辑。
