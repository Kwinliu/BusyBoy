# 素材与服务

## 应用素材

- `Sources/PaperTodo/Resources/printer-busyboy.png`：白色打印机与儿童贴纸，由生成式图像工具制作并保存到项目。
- `Sources/PaperTodo/Resources/thermal-paper.png`：细微热敏纸纹理，由生成式图像工具制作。
- 纸张轮廓、出纸光影、热敏文字缺陷、马克笔、指示灯、机械连杆、世界时钟、数显屏和动画由 SwiftUI / AppKit 原生代码绘制。
- 打印、撕纸与机械按键声由本机 PCM 合成；未将开发过程中试听的系统提示音或声音草稿纳入发行包。
- 图文说明中的截图来自独立演示实例，使用示例内容；不是产品效果图。

生成素材的设计规格为：透明背景的白色热敏打印机，带白边的地球、闹钟、太阳云朵和剪刀贴纸，保留 BusyBoy 字样、绿灯、按钮及黑色出纸槽。等宽纸张由原生界面单独绘制，便于真实送纸。

## 在线服务

天气预报与城市检索使用 [Open-Meteo](https://open-meteo.com/)，城市资料基于 GeoNames。客户端会向服务发送查询的城市名称或城市坐标，不发送待办内容。服务不可用时会提示，已有天气缓存仍可显示。

- [天气 API 文档](https://open-meteo.com/en/docs)
- [城市检索 API 文档](https://open-meteo.com/en/docs/geocoding-api)

系统字体、SF Symbols 与系统结束提示音通过 macOS 框架使用。
