import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 10.0
    @AppStorage("playerDictUrl") private var playerDictUrl: String = ""
    @State private var updateMessage = ""
    @State private var isUpdating = false
    
    var body: some View {
        TabView {
            // General Tab
            Form {
                Section {
                    HStack(alignment: .top, spacing: 20) {
                        Text("刷新频率:")
                            .frame(width: 80, alignment: .trailing)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Slider(value: $refreshInterval, in: 5...60, step: 1)
                                    .frame(width: 180)
                                Text("\(Int(refreshInterval)) 秒")
                                    .frame(width: 40, alignment: .trailing)
                            }
                            Text("建议设置在 10~15 秒之间，设置过低可能会导致\n接口屏蔽此局域网 IP。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
            .frame(width: 450, height: 200)
            .tabItem {
                Label("通用", systemImage: "gearshape")
            }
            
            // Dictionary Tab
            Form {
                Section {
                    HStack(alignment: .top, spacing: 20) {
                        Text("云端词典:")
                            .frame(width: 80, alignment: .trailing)
                            .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("JSON URL 链接", text: $playerDictUrl)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: .infinity)
                            
                            Text("配置后，应用会在每次冷启动时自动拉取更新解析中文化。\n支持标准字典以及带 players 数组的深层结构。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Button(action: fetchRemoteDictionary) {
                                    Text(isUpdating ? "正在拉取..." : "立即手动拉取更新")
                                }
                                .disabled(playerDictUrl.isEmpty || isUpdating)
                                
                                if !updateMessage.isEmpty {
                                    Text(updateMessage)
                                        .font(.caption)
                                        .foregroundColor(updateMessage.contains("成功") ? .green : .red)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(20)
            .frame(width: 500, height: 250)
            .tabItem {
                Label("数据源配置", systemImage: "network")
            }
        }
        .frame(width: 500)
    }
    
    func fetchRemoteDictionary() {
        guard let url = URL(string: playerDictUrl) else {
            updateMessage = "错误的 URL 格式"
            return
        }
        isUpdating = true
        updateMessage = "正在通过网络获取配置..."
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData // 强制不走缓存获取最新
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                self.isUpdating = false
                if let _ = error {
                    self.updateMessage = "拉取失败，请检查网络或链接是否可用"
                    return
                }
                
                guard let data = data else {
                    self.updateMessage = "数据为空"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let players = json["players"] as? [[String: Any]] {
                        
                        var newMapping: [String: String] = [:]
                        for player in players {
                            if let displayName = player["displayName"] as? String,
                               let lastName = player["lastName"] as? String,
                               let firstName = player["firstName"] as? String {
                                
                                // 根据中文习惯，拼接 firstName 和 lastName 作为中文全名
                                // 注意在这个 JSON 中，如“恩比德”(LastName) + “乔尔”(FirstName) => "乔尔-恩比德" 或直接用 lastName 等，
                                // 这里使用 firstName + lastName 合并，如没有 firstName 则只用 lastName
                                let zhName = firstName.isEmpty ? lastName : "\(firstName) \(lastName)"
                                newMapping[displayName] = zhName.trimmingCharacters(in: .whitespaces)
                            }
                        }
                        
                        if !newMapping.isEmpty {
                            PlayerTranslator.shared.updateCustomMapping(newMapping)
                            self.updateMessage = "成功！本次共拉取并更新了 \(newMapping.count) 条球员翻译映射。"
                        } else {
                            self.updateMessage = "拉取成功，但未能解析出球员列表，请检查 [players] 数组结构。"
                        }
                    } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                        // 兼容老的纯 [String: String] 格式
                        PlayerTranslator.shared.updateCustomMapping(json)
                        self.updateMessage = "成功！本次共拉取并更新了 \(json.count) 条球员翻译映射。"
                    } else {
                        self.updateMessage = "解析失败：无法识别的 JSON 结构"
                    }
                } catch {
                    self.updateMessage = "解析严重失败：JSON 语法错误 (\(error.localizedDescription))"
                }
            }
        }.resume()
    }
}
