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

    async function updateServiceStatus() {
        try {
            const response = await fetch('/check_status');
            if (!response.ok) {
                throw new Error('检查状态失败：' + response.statusText);
            }
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
            const response = await fetch(`/get_rules?page=${currentPage}&size=${pageSize}`, {
                method: 'GET',
                headers: {
                    'Cache-Control': 'no-cache',
                    'Pragma': 'no-cache'
                },
            });
    
            if (!response.ok) {
                throw new Error('获取规则失败：' + response.statusText);
            }
    
            const data = await response.json();
            const rules = data.rules || [];
            if (!Array.isArray(data.rules)) {
                throw new Error('服务器返回的数据格式不正确');
            }

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

            const localPort = listen.split(':')[1];
            const lastColonIndex = remote.lastIndexOf(':');
            const remoteIP = remote.substring(0, lastColonIndex);
            const remotePort = remote.substring(lastColonIndex + 1);

            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${index + 1}</td>
                <td>${localPort}</td>
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

    function goToPrevPage() {
        if (currentPage > 1) {
            currentPage--;
            fetchForwardingRules();
        }
    }

    function goToNextPage() {
        const totalPages = Math.ceil(totalRules / pageSize);
        if (currentPage < totalPages) {
            currentPage++;
            fetchForwardingRules();
        }
    }

    async function deleteRule(listenAddress) {
        try {
            const response = await fetch(`/delete_rule?listen=${encodeURIComponent(listenAddress)}`, {
                method: 'DELETE'
            });

            if (!response.ok) {
                throw new Error('删除规则失败：' + response.statusText);
            }

            const restartResponse = await fetch('/restart_service', {
                method: 'POST'
            });
            if (!restartResponse.ok) {
                throw new Error('重启服务失败：' + restartResponse.statusText);
            }

            outputDiv.textContent = '规则已删除，服务已重启';
            await fetchForwardingRules();
            await updateServiceStatus();
        } catch (error) {
            console.error('删除失败:', error);
            outputDiv.textContent = error.message;
        }
    }

    async function addRule() {
        const localPort = localPortInput.value.trim();
        const remoteIP = remoteIPInput.value.trim();
        const remotePort = remotePortInput.value.trim();

        if (!localPort || !remoteIP || !remotePort) {
            outputDiv.textContent = '请填写所有字段';
            return;
        }

        try {
            const usedPorts = new Set(allRules.map(r => r.listen.split(':')[1]));
            if (usedPorts.has(localPort)) {
                outputDiv.textContent = `端口 ${localPort} 已被占用`;
                return;
            }

            const response = await fetch('/add_rule', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    listen: `0.0.0.0:${localPort}`,
                    remote: `${remoteIP}:${remotePort}`
                })
            });

            if (!response.ok) {
                throw new Error('添加规则失败：' + response.statusText);
            }

            const restartResponse = await fetch('/restart_service', {
                method: 'POST'
            });
            if (!restartResponse.ok) {
                throw new Error('重启服务失败：' + restartResponse.statusText);
            }

            outputDiv.textContent = '规则添加成功，服务已重启';
            localPortInput.value = '';
            remoteIPInput.value = '';
            remotePortInput.value = '';
            await fetchForwardingRules();
            await updateServiceStatus();
        } catch (error) {
            console.error('添加失败:', error);
            outputDiv.textContent = error.message;
        }
    }

    async function addBatchRules() {
        const rules = rulesInput.value.trim().split('\n').filter(Boolean);
        if (rules.length === 0) {
            outputDiv.textContent = '请输入要添加的规则';
            return;
        }

        const usedPorts = new Set(allRules.map(r => r.listen.split(':')[1]));
        const failedRules = [];
        let hasSuccess = false;

        for (const rule of rules) {
            const match = rule.match(/^(\d+):(\[.*?\]:\d+|\S+)$/);
            if (!match) {
                failedRules.push(`格式错误: ${rule}`);
                continue;
            }

            const localPort = match[1];
            const remoteAddress = match[2];

            if (usedPorts.has(localPort)) {
                failedRules.push(`端口 ${localPort} 已被占用`);
                continue;
            }

            try {
                const response = await fetch('/add_rule', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        listen: `0.0.0.0:${localPort}`,
                        remote: remoteAddress
                    })
                });

                if (!response.ok) {
                    failedRules.push(`添加失败: ${rule}`);
                    continue;
                }

                usedPorts.add(localPort);
                hasSuccess = true;
            } catch (error) {
                failedRules.push(`添加失败: ${rule} - ${error.message}`);
            }
        }

        if (hasSuccess) {
            try {
                const restartResponse = await fetch('/restart_service', {
                    method: 'POST'
                });
                if (!restartResponse.ok) {
                    throw new Error('重启服务失败');
                }
            } catch (error) {
                failedRules.push('服务重启失败');
            }
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
        try {
            const response = await fetch('/start_service', {
                method: 'POST'
            });
            if (!response.ok) {
                throw new Error('启动服务失败：' + response.statusText);
            }
            outputDiv.textContent = '服务启动成功';
            await updateServiceStatus();
        } catch (error) {
            console.error('启动失败:', error);
            outputDiv.textContent = error.message;
        }
    });

    stopButton.addEventListener('click', async () => {
        try {
            const response = await fetch('/stop_service', {
                method: 'POST'
            });
            if (!response.ok) {
                throw new Error('停止服务失败：' + response.statusText);
            }
            outputDiv.textContent = '服务停止成功';
            await updateServiceStatus();
        } catch (error) {
            console.error('停止失败:', error);
            outputDiv.textContent = error.message;
        }
    });

    restartButton.addEventListener('click', async () => {
        try {
            const response = await fetch('/restart_service', {
                method: 'POST'
            });
            if (!response.ok) {
                throw new Error('重启服务失败：' + response.statusText);
            }
            outputDiv.textContent = '服务重启成功';
            await updateServiceStatus();
        } catch (error) {
            console.error('重启失败:', error);
            outputDiv.textContent = error.message;
        }
    });

    logoutButton.addEventListener('click', async () => {
        try {
            const response = await fetch('/logout', {
                method: 'POST'
            });
            if (response.ok) {
                window.location.href = '/login';
            } else {
                throw new Error('登出失败：' + response.statusText);
            }
        } catch (error) {
            console.error('登出失败:', error);
            outputDiv.textContent = error.message;
        }
    });

    addRuleButton.addEventListener('click', addRule);
    addBatchRulesButton.addEventListener('click', addBatchRules);

    document.getElementById('prevPage').addEventListener('click', goToPrevPage);
    document.getElementById('nextPage').addEventListener('click', goToNextPage);

    pageSizeSelect.addEventListener('change', () => {
        pageSize = parseInt(pageSizeSelect.value, 10);
        currentPage = 1;
        fetchForwardingRules();
    });

    fetchForwardingRules();
    updateServiceStatus();
    
    setInterval(updateServiceStatus, 15000);
});
