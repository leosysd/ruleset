# Sing Geosite 规则构建仓库

这个仓库用于每周自动构建一组固定输出规则，路由器只需要下载成品，不再承担反编译、合并和编译压力。

## 输入

- `lists/direct.txt`：直连 geosite 规则标签，每行一个。
- `lists/direct-add.txt`：额外直连域名，每行一个；默认按 `domain_suffix` 处理，也支持 `full:`、`domain:`、`suffix:`、`keyword:`、`regexp:` 前缀。
- `lists/proxy.txt`：代理 geosite 规则标签，每行一个。
- `lists/direct-exclude.txt`：从直连成品里强制排除的具体域名，每行一个。

如果同一个 geosite 标签同时出现在 `direct.txt` 和 `proxy.txt`，构建时会从直连列表里剔除，保留代理列表里的标签。

规则名可以写成 `google`，也可以写成 `geosite-google.srs`。空行和 `#` 注释会被忽略。

## 输出

构建完成后，`dist/` 只保留三组共 6 个成品文件：

- sing-box 二进制规则集
  - `direct-geosite.srs`
  - `proxy-geosite.srs`
- mosdns 规则集
  - `direct-geosite.txt`
  - `proxy-geosite.txt`
- JSON 规则集
  - `direct-geosite.json`
  - `proxy-geosite.json`

`dist/` 不放扫描日志、配置片段或 manifest，避免路由器下载时混淆。

## 每周自动构建

GitHub Actions 会每周二北京时间 07:30 自动运行：

```yaml
schedule:
  - cron: "30 23 * * 1"
```

这里的时间是 UTC，等于北京时间周二 07:30。

## 路由器侧使用建议

OpenWrt 路由器可以只下载 `dist/` 内成品：

- `/etc/sing-box/rule-set/direct-geosite.srs`
- `/etc/sing-box/rule-set/proxy-geosite.srs`
- `/etc/sing-box/rule-set/direct-geosite.json`
- `/etc/sing-box/rule-set/proxy-geosite.json`
- `/etc/mosdns/rule/direct-geosite.txt`
- `/etc/mosdns/rule/proxy-geosite.txt`

插件不需要修改 sing-box 主配置，也不需要修改 inbound、outbound、节点或 mosdns 主逻辑。

可以安装仓库里的更新脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/leosysd/ruleset/main/install.sh | sh
```

默认 cron 是每周二北京时间 07:45 拉取 GitHub 生成好的 6 个成品文件。

如果路由器没有 `curl`，可以用：

```bash
wget -O- https://raw.githubusercontent.com/leosysd/ruleset/main/install.sh | sh
```

卸载自动更新脚本：

```bash
/usr/bin/update-geosite-rules remove-cron
rm -f /usr/bin/update-geosite-rules
```

上面只会删除自动更新脚本和 cron，不会删除已经生成的规则文件。

### mosdns + sing-box DNS 劫持处理

如果 sing-box 的 `auto_redirect` 自动生成了 53 端口 DNS DNAT，而你的 DNS 流程由 mosdns 接管，可以安装这个辅助脚本：

```bash
wget -O /usr/bin/sing-box-disable-dns-hijack \
  https://raw.githubusercontent.com/leosysd/ruleset/main/openwrt/sing-box-disable-dns-hijack.sh
chmod +x /usr/bin/sing-box-disable-dns-hijack
```

这个脚本只删除 `inet sing-box` 表里由 sing-box 生成的 53 端口 DNAT，不会删除 OpenWrt fw4 的 DNS 重定向规则。

卸载这个辅助脚本：

```bash
rm -f /usr/bin/sing-box-disable-dns-hijack
```

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
