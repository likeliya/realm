document.addEventListener('DOMContentLoaded', () => {
    const outputDiv = document.getElementById('output');
    const startButton = document.getElementById('startButton');
    const stopButton = document.getElementById('stopButton');
    const restartButton = document.getElementById('restartButton');
    const addRuleButton = document.getElementById('addRuleButton');
    const addBatchRulesButton = document.getElementById('addBatchRulesButton');
    const logoutButton = document.getElementById('logoutButton');
    const localPortInput = document.getElementById('localPort');
    const remoteIPInput = document.getElementById('remoteIP');
    const remotePortInput = document.getElementById('remotePort');
    const rulesInput = document.getElementById('rulesInput');

    let allRules = [];
    let currentPage = 1;
    let pageSize = 10;
    let totalRules = 0;

    const pageSizeSelect = document.getElementById('pageSizeSelect');

    // === 核心新增：动态注入入口 IP 选择框 ===
    if (localPortInput && !document.getElementById('listenType')) {
        const select = document.createElement('select');
        select.id = 'listenType';
        select.innerHTML = '<option value="0.0.0.0">入口: IPv4</option><option value="[::]">入口: IPv6/双栈</option>';
        select.style.marginRight = '10px';
        select.style.padding = '5px';
        select.style.borderRadius = '4px';
        // 插入到本地端口输入框的前面
        localPortInput.parentNode.insertBefore(select, localPortInput);
    }

    async function updateServiceStatus() {
        try {
            const response = await fetch('/check_status');
            if (!response.ok) throw new Error('检查状态失败：' + response.statusText);
            const data = await response.json();
            const statusElement = document.getElementById('serviceStatus');
            
            if (data.status === "启用") {
                statusElement.textContent = "运行中";
                statusElement.className = 'status-tag running';
            } else {
                statusElement.textContent = "已停止";
                statusElement.className = 'status-tag stopped';
            }
        } catch (error) {
            console.error('状态检查失败:', error);
            const statusElement = document.getElementById('serviceStatus');
            statusElement.textContent = "未知";
            statusElement.className = 'status-tag stopped';
        }
    }

    async function fetchForwardingRules() {
        try {
            const response = await fetch(`/get_rules?page=${currentPage}&size=${pageSize}&t=${new Date().getTime()}`, {
                method: 'GET',
                headers: { 'Cache-Control': 'no-cache', 'Pragma': 'no-cache' },
            });
    
            if (!response.ok) throw new Error('获取规则失败：' + response.statusText);
    
            const data = await response.json();
            if (!Array.isArray(data.rules)) throw new Error('服务器返回的数据格式不正确');

            totalRules = data.total;
            allRules = data.rules.map(rule => {
                const listen = rule.Listen || rule.listen;
                const remote = rule.Remote || rule.remote;
                return { listen, remote };
            });

            renderForwardingRules();
            return allRules;
        } catch (error) {
            console.error('获取规则失败:', error);
            outputDiv.textContent = `获取转发规则失败: ${error.message}`;
            return [];
        }
    }

    function renderForwardingRules() {
        const tbody = document.querySelector('#forwardingTable tbody');
        tbody.innerHTML = '';

        allRules.forEach((rule, index) => {
            const listen = rule.listen;
            const remote = rule.remote;

            // 提取正确的本地端口与远程信息
            const localPort = listen.substring(listen.lastIndexOf(':') + 1);
            const lastColonIndex = remote.lastIndexOf(':');
            const remoteIP = remote.substring(0, lastColonIndex);
            const remotePort = remote.substring(lastColonIndex + 1);

            // 给入口类型打上醒目的标签
            const badge = listen.includes('[::]') 
                ? '<span style="color:#00d2ff; font-weight:bold; margin-right:6px;">[IPv6]</span>' 
                : '<span style="color:#00ff88; font-weight:bold; margin-right:6px;">[IPv4]</span>';

            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${index + 1}</td>
                <td>${badge}${localPort}</td>
                <td>${remoteIP}</td>
                <td>${remotePort}</td>
                <td><button class="delete-btn" data-listen="${listen}">删除</button></td>
            `;
            tbody.appendChild(row);
        });

        document.querySelectorAll('.delete-btn').forEach(button => {
            button.addEventListener('click', function() {
                deleteRule(this.getAttribute('data-listen'));
            });
        });

        updatePaginationInfo();
    }

    function updatePaginationInfo() {
        const pageInfo = document.getElementById('pageInfo');
        const totalPages = Math.ceil(totalRules / pageSize);
        pageInfo.textContent = `第 ${currentPage} / ${totalPages === 0 ? 1 : totalPages} 页`;
        document.getElementById('prevPage').disabled = (currentPage <= 1);
        document.getElementById('nextPage').disabled = (currentPage >= totalPages || totalPages === 0);
    }

    function goToPrevPage() { if (currentPage > 1) { currentPage--; fetchForwardingRules(); } }
    function goToNextPage() {
        const totalPages = Math.ceil(totalRules / pageSize);
        if (currentPage < totalPages) { currentPage++; fetchForwardingRules(); }
    }

    async function deleteRule(listenAddress) {
        try {
            const response = await fetch(`/delete_rule?listen=${encodeURIComponent(listenAddress)}`, { method: 'DELETE' });
            if (!response.ok) throw new Error('删除规则失败：' + response.statusText);
            
            await fetch('/restart_service', { method: 'POST' });
            outputDiv.textContent = '规则已删除，服务已重启';
            await fetchForwardingRules();
            await updateServiceStatus();
        } catch (error) { outputDiv.textContent = error.message; }
    }

    async function addRule() {
        const listenType = document.getElementById('listenType') ? document.getElementById('listenType').value : '0.0.0.0';
        const localPort = localPortInput.value.trim();
        const remoteIP = remoteIPInput.value.trim();
        const remotePort = remotePortInput.value.trim();

        if (!localPort || !remoteIP || !remotePort) {
            outputDiv.textContent = '请填写所有字段';
            return;
        }

        try {
            const usedPorts = new Set(allRules.map(r => r.listen.substring(r.listen.lastIndexOf(':') + 1)));
            if (usedPorts.has(localPort)) {
                outputDiv.textContent = `端口 ${localPort} 已被占用`;
                return;
            }

            // 自动为 IPv6 添加方括号
            let safeRemoteIP = remoteIP;
            if (safeRemoteIP.includes(':') && !safeRemoteIP.startsWith('[')) {
                safeRemoteIP = `[${safeRemoteIP}]`;
            }

            const response = await fetch('/add_rule', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    listen: `${listenType}:${localPort}`,
                    remote: `${safeRemoteIP}:${remotePort}`
                })
            });

            if (!response.ok) throw new Error('添加规则失败：' + response.statusText);
            
            await fetch('/restart_service', { method: 'POST' });
            outputDiv.textContent = '规则添加成功，服务已重启';
            localPortInput.value = ''; remoteIPInput.value = ''; remotePortInput.value = '';
            await fetchForwardingRules();
            await updateServiceStatus();
        } catch (error) { outputDiv.textContent = error.message; }
    }

    async function addBatchRules() {
        const rules = rulesInput.value.trim().split('\n').filter(Boolean);
        if (rules.length === 0) {
            outputDiv.textContent = '请输入要添加的规则';
            return;
        }

        const listenType = document.getElementById('listenType') ? document.getElementById('listenType').value : '0.0.0.0';
        const usedPorts = new Set(allRules.map(r => r.listen.substring(r.listen.lastIndexOf(':') + 1)));
        const failedRules = [];
        let hasSuccess = false;

        for (const rule of rules) {
            const firstColon = rule.indexOf(':');
            if (firstColon === -1) {
                failedRules.push(`格式错误: ${rule}`);
                continue;
            }

            const localPort = rule.substring(0, firstColon);
            let remoteAddress = rule.substring(firstColon + 1);

            if (usedPorts.has(localPort)) {
                failedRules.push(`端口 ${localPort} 已被占用`);
                continue;
            }

            // 终极修复：批量添加也能智能识别 IPv6 并套上方括号
            const colonsCount = (remoteAddress.match(/:/g) || []).length;
            if (colonsCount >= 2 && !remoteAddress.startsWith('[')) {
                const lastColon = remoteAddress.lastIndexOf(':');
                const ip = remoteAddress.substring(0, lastColon);
                const port = remoteAddress.substring(lastColon + 1);
                remoteAddress = `[${ip}]:${port}`;
            }

            try {
                const response = await fetch('/add_rule', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        listen: `${listenType}:${localPort}`,
                        remote: remoteAddress
                    })
                });

                if (!response.ok) {
                    failedRules.push(`添加失败: ${rule}`);
                    continue;
                }
                usedPorts.add(localPort);
                hasSuccess = true;
            } catch (error) { failedRules.push(`添加失败: ${rule} - ${error.message}`); }
        }

        if (hasSuccess) {
            try { await fetch('/restart_service', { method: 'POST' }); } 
            catch (error) { failedRules.push('服务重启失败'); }
        }

        rulesInput.value = '';
        await fetchForwardingRules();
        await updateServiceStatus();

        if (failedRules.length > 0) {
            outputDiv.textContent = `添加完成。\n失败的规则：\n${failedRules.join('\n')}`;
        } else {
            outputDiv.textContent = '所有规则添加成功，服务已重启';
        }
    }

    startButton.addEventListener('click', async () => {
        try { await fetch('/start_service', { method: 'POST' }); outputDiv.textContent = '服务启动成功'; await updateServiceStatus(); } catch (error) { outputDiv.textContent = error.message; }
    });
    stopButton.addEventListener('click', async () => {
        try { await fetch('/stop_service', { method: 'POST' }); outputDiv.textContent = '服务停止成功'; await updateServiceStatus(); } catch (error) { outputDiv.textContent = error.message; }
    });
    restartButton.addEventListener('click', async () => {
        try { await fetch('/restart_service', { method: 'POST' }); outputDiv.textContent = '服务重启成功'; await updateServiceStatus(); } catch (error) { outputDiv.textContent = error.message; }
    });
    logoutButton.addEventListener('click', async () => {
        try {
            const response = await fetch('/logout', { method: 'POST' });
            if (response.ok) window.location.href = '/login'; else throw new Error('登出失败');
        } catch (error) { outputDiv.textContent = error.message; }
    });

    addRuleButton.addEventListener('click', addRule);
    addBatchRulesButton.addEventListener('click', addBatchRules);
    document.getElementById('prevPage').addEventListener('click', goToPrevPage);
    document.getElementById('nextPage').addEventListener('click', goToNextPage);

    pageSizeSelect.addEventListener('change', () => {
        pageSize = parseInt(pageSizeSelect.value, 10);
        currentPage = 1; fetchForwardingRules();
    });

    fetchForwardingRules();
    updateServiceStatus();
    setInterval(updateServiceStatus, 15000);
});
