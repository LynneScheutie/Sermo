import Foundation

/// 顶部「设置」入口。
///
/// Aether 页面本身没有 API 入口——在 Lawlearn 里这一步由主程序的设置页完成。
/// 独立版没有主程序，所以把入口补回页面：在 `.top` 顶部栏末尾追加一个「⚙ 设置」
/// 按钮，点开是服务商 / API Key / 模型三项。
///
/// 采用注入而不是改 HTML 源文件的理由：页面是 2 MB 的单字符串字面量，
/// 直接改会牵动整块内容；注入只影响运行期，原页面一行不动，行为可预测。
///
/// 与 Swift 的往来：
///   JS → Swift  window.webkit.messageHandlers.aetherBridge.postMessage({type:"settings", action:"get"|"save", ...})
///   Swift → JS  window.__sermoPrefs({key, providerID, model, providers:[...]})
enum SermoSettingsJS {

    static let install = #"""
    (function () {
      if (document.getElementById('sermo-set-btn')) return;
      var top = document.querySelector('.top');
      if (!top) return;

      var btn = document.createElement('button');
      btn.className = 'tbtn';
      btn.id = 'sermo-set-btn';
      btn.textContent = '⚙ 设置';
      btn.title = '设置 API';
      top.appendChild(btn);

      var mask = document.createElement('div');
      mask.id = 'sermo-set-mask';
      mask.style.cssText = 'position:fixed;left:0;top:0;right:0;bottom:0;background:rgba(0,0,0,.38);'
        + 'display:none;align-items:center;justify-content:center;z-index:99999';
      mask.innerHTML = [
        '<div style="width:430px;max-width:88vw;background:#fff;color:#1a1a1a;border-radius:14px;',
          'padding:20px 22px;box-shadow:0 18px 60px rgba(0,0,0,.30);font-size:14px;text-align:left">',
          '<div style="font-size:16px;font-weight:600;margin-bottom:16px">设置</div>',
          '<div style="margin-bottom:12px"><div style="margin-bottom:6px">服务商</div>',
            '<select id="sermo-prov" style="width:100%;padding:8px 10px;border:1px solid #d8d8dd;',
            'border-radius:8px;font-size:14px;background:#fff;color:#1a1a1a"></select></div>',
          '<div style="margin-bottom:12px"><div style="margin-bottom:6px">API Key</div>',
            '<input id="sermo-key" type="text" autocomplete="off" spellcheck="false" placeholder="粘贴 API Key" ',
            'style="width:100%;padding:8px 10px;border:1px solid #d8d8dd;border-radius:8px;font-size:14px;',
            'font-family:ui-monospace,Menlo,monospace" /></div>',
          '<div style="margin-bottom:12px"><div style="margin-bottom:6px">模型（留空则用默认）</div>',
            '<input id="sermo-model" type="text" autocomplete="off" spellcheck="false" ',
            'style="width:100%;padding:8px 10px;border:1px solid #d8d8dd;border-radius:8px;font-size:14px" /></div>',
          '<div id="sermo-hint" style="color:#8a8a8f;font-size:12px;line-height:1.6;margin:10px 0 18px"></div>',
          '<div style="display:flex;gap:10px;justify-content:flex-end">',
            '<button id="sermo-cancel" class="tbtn">取消</button>',
            '<button id="sermo-save" class="tbtn primary">保存</button>',
          '</div>',
        '</div>'
      ].join('');

      document.body.appendChild(mask);

      function send(msg) {
        try { window.webkit.messageHandlers.aetherBridge.postMessage(msg); } catch (e) {}
      }

      function fill(d) {
        var sel = document.getElementById('sermo-prov');
        sel.innerHTML = '';
        (d.providers || []).forEach(function (p) {
          var o = document.createElement('option');
          o.value = p.id;
          o.textContent = p.name + '（默认 ' + p.defaultModel + '）';
          if (p.id === d.providerID) o.selected = true;
          sel.appendChild(o);
        });
        document.getElementById('sermo-key').value = d.key || '';
        document.getElementById('sermo-model').value = d.model || '';
        var hint = document.getElementById('sermo-hint');
        if ((d.key || '').length >= 20) {
          hint.textContent = '已配置。当前生效：' + (sel.options[sel.selectedIndex] || {}).text;
        } else {
          hint.textContent = '尚未配置 API Key。保存后即可开始对话。';
        }
      }

      function open() {
        mask.style.display = 'flex';
        send({ type: 'settings', action: 'get' });
        setTimeout(function () { document.getElementById('sermo-key').focus(); }, 60);
      }
      function close() { mask.style.display = 'none'; }

      btn.addEventListener('click', open);
      document.getElementById('sermo-cancel').addEventListener('click', close);
      mask.addEventListener('click', function (e) { if (e.target === mask) close(); });
      document.getElementById('sermo-save').addEventListener('click', function () {
        var sel = document.getElementById('sermo-prov');
        send({
          type: 'settings',
          action: 'save',
          key: document.getElementById('sermo-key').value || '',
          providerID: sel.value || '',
          model: document.getElementById('sermo-model').value || ''
        });
      });
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && mask.style.display === 'flex') close();
      });

      window.__sermoPrefs = fill;
      window.__sermoOpenSettings = open;
      window.__sermoCloseSettings = close;
    })();
    """#

    /// 保存成功后刷新提示文字并关闭面板
    static let saved = #"""
    (function(){ var m = document.getElementById('sermo-set-mask'); if (m) m.style.display = 'none'; })();
    """#
}
