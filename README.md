# HSE现场打卡

面向核电施工现场的离线 Android 打卡应用。第一版用于记录施工单位安全人员在岗履职情况，数据和照片仅保存在手机本地。

## 已实现

- 首次设置并保存巡检员姓名
- 新增、编辑、删除安全员在岗检查记录
- 施工单位和检查区域历史输入建议
- 白班/夜班、报送人数、在岗状态及缺岗整改信息校验
- 每条记录拍摄并保存 1～3 张照片
- 按日期、单位、区域和班次筛选历史记录
- 按日期范围导出带嵌入照片的标准 `.xlsx` 检查表
- 导出文件保存及系统分享

## 开发与构建

项目要求 Flutter 3.47 或兼容版本、JDK 21 和 Android SDK。最低 Android 版本为 Android 8.0（API 26）。

```text
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

发布 APK 默认位于 `build/app/outputs/flutter-apk/app-release.apk`。

## 数据说明

- SQLite 数据库：应用数据库目录中的 `hse_attendance.db`
- 照片：应用文档目录下 `photos/年/月/日/`
- 导出兜底目录：应用文档目录下 `exports/`

卸载应用会清除本地数据库和照片。备份恢复功能不在第一版范围内。
