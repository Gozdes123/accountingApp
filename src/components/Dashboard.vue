<script setup>
import { ref, onMounted, onActivated, onUnmounted, computed, watch } from 'vue'
import { supabase } from '../lib/supabaseClient'
import { Chart as ChartJS, ArcElement, Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Title, Filler, BarElement } from 'chart.js'
import { Doughnut, Line, Bar } from 'vue-chartjs'
import BottomNav from './BottomNav.vue'
import { 
  PhEye, PhEyeSlash, PhPlus, PhTrash, PhWallet, PhTrendUp, 
  PhArrowDownLeft, PhBank, PhCoins, PhCalendar, PhArrowClockwise, PhCaretLeft, PhCaretRight,
  PhHouse, PhCar, PhLock, PhUsers, PhCreditCard,
  PhCloudArrowUp, PhCards, PhCurrencyCny, PhChartBar, PhCurrencyBtc, PhLeaf, PhBuildings, PhCube,
  PhCheck, PhAppleLogo, PhWechatLogo, PhBookOpen, PhUser, PhCheckCircle, PhInfo, PhMinusCircle, PhQrCode, PhCaretDown, PhCaretUp
} from '@phosphor-icons/vue'

ChartJS.register(ArcElement, Tooltip, Legend, CategoryScale, LinearScale, PointElement, LineElement, Title, Filler, BarElement)

// ── State ─────────────────────────────────────────────────────────
const currentTab = ref('list') // list, trend, settings
const showStatsModal = ref(false)
const statsType = ref('invest') // invest, liquid
const statsTimeFilter = ref('6M') // 5W, 6M, 1Y, YTD, 4Y
const syncAccountBalance = ref(false)
const todayTransactions = ref([])

const handleBottomNavClick = (tabId) => {
  if (tabId === 'list') {
    if (currentTab.value === 'list') {
      showStatsModal.value = true
    } else {
      currentTab.value = 'list'
    }
  } else {
    currentTab.value = tabId
    showStatsModal.value = false
  }
}

const shareStats = () => {
  if (navigator.share) {
    navigator.share({
      title: '收支統計',
      text: '我的收支與投資變動統計',
      url: window.location.href
    }).catch(() => {})
  } else {
    showToast('已複製統計資訊連結')
  }
}

const statsChartData = computed(() => {
  // 1. 動態計算最近 6 個月的標籤與年/月對照 (例如 2月, 3月, 4月, 5月, 6月, 7月)
  const today = new Date()
  const months = []
  const monthKeys = []
  for (let i = 5; i >= 0; i--) {
    const d = new Date(today.getFullYear(), today.getMonth() - i, 1)
    months.push(`${d.getMonth() + 1}月`)
    monthKeys.push({ year: d.getFullYear(), month: d.getMonth() })
  }
  
  if (statsType.value === 'invest') {
    // 獲取最近 6 個月歷史持倉成本與累計盈虧的真實數據
    const costData = []
    const pnlData = []
    
    monthKeys.forEach(({ year, month }) => {
      // 找出該年該月在 historyRecords 中的最後一筆快照紀錄
      const monthRecords = historyRecords.value.filter(r => {
        const d = new Date(r.date)
        return d.getFullYear() === year && d.getMonth() === month
      })
      
      let cost = 0
      let pnl = 0
      
      if (monthRecords.length > 0) {
        const lastRec = monthRecords[monthRecords.length - 1]
        let valTwd = 0
        let costTwd = 0
        
        if (lastRec.details) {
          if (Array.isArray(lastRec.details.investments)) {
            // 從快照詳細明細中加總
            lastRec.details.investments.forEach(inv => {
              const val = Number(inv.quantity || 0) * Number(inv.current_price || 0)
              const c = Number(inv.quantity || 0) * Number(inv.average_cost || 0)
              const rate = inv.currency === 'USD' ? usdTwdRate.value : 1
              valTwd += val * rate
              costTwd += c * rate
            })
          } else {
            // 相容舊有格式
            valTwd = Number(lastRec.details.investments_value || 0)
            costTwd = Number(lastRec.details.investments_cost || 0)
          }
        }
        cost = Math.round(costTwd)
        pnl = Math.round(valTwd - costTwd)
      }
      
      costData.push(cost)
      pnlData.push(pnl)
    })
    
    // 如果當月（最後一個月）還沒有寫入資料庫快照，強制與當前最即時的實際數據對齊，避免顯示為 0
    const activePnL = investments.value.reduce((sum, item) => {
      const qty = Number(item.quantity || 0)
      const current = Number(item.current_price || 0)
      const cost = Number(item.buy_price || item.average_cost || 0)
      const raw = qty * (current - cost)
      const currency = item.currency || 'TWD'
      return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
    }, 0)
    
    const activeCost = investments.value.reduce((sum, item) => {
      const qty = Number(item.quantity || 0)
      const cost = Number(item.buy_price || item.average_cost || 0)
      const raw = qty * cost
      const currency = item.currency || 'TWD'
      return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
    }, 0)
    
    costData[5] = Math.round(activeCost)
    pnlData[5] = Math.round(activePnL)
    
    return {
      labels: months,
      datasets: [
        {
          label: '持倉成本',
          backgroundColor: '#ccd7f5',
          borderRadius: 8,
          data: costData
        },
        {
          label: '累計盈虧',
          backgroundColor: '#5c67f5',
          borderRadius: 8,
          data: pnlData
        }
      ]
    }
  } else {
    // statsType === 'liquid'
    // 取得當前設定的所有定期定額/定期記帳預估總額
    let monthlyIncome = 0
    let monthlyExpense = 0
    accounts.value.forEach(acc => {
      if (acc.auto_record) {
        let records = []
        if (Array.isArray(acc.auto_record)) {
          records = acc.auto_record
        } else if (acc.auto_record.enabled) {
          records = [acc.auto_record]
        }
        records.forEach(ar => {
          if (ar.enabled) {
            const arCurrency = ar.currency || 'TWD'
            let amtTwd = Number(ar.amount || 0)
            if (arCurrency === 'USD') {
              amtTwd = amtTwd * usdTwdRate.value
            } else if (arCurrency === 'JPY') {
              amtTwd = amtTwd * (jpyTwdRate.value || 0.22)
            }
            
            if (ar.type === 'income') {
              monthlyIncome += amtTwd
            } else if (ar.type === 'expense' || ar.type === 'dca_invest') {
              monthlyExpense += amtTwd
            }
          }
        })
      }
    })
    
    const finalIncome = Math.round(monthlyIncome)
    const finalExpense = Math.round(monthlyExpense)
    
    const incomeData = Array(6).fill(finalIncome)
    const expenseData = Array(6).fill(finalExpense)
    
    return {
      labels: months,
      datasets: [
        {
          label: '預估月收入',
          backgroundColor: '#2ebd59',
          borderRadius: 8,
          data: incomeData
        },
        {
          label: '預估月支出',
          backgroundColor: '#e2e8f0',
          borderRadius: 8,
          data: expenseData
        }
      ]
    }
  }
})

const statsSummaryText = computed(() => {
  const today = new Date()
  const start = new Date(today.getFullYear(), today.getMonth() - 5, 1)
  const end = today
  const dynamicTitle = `${start.getFullYear()}年${start.getMonth() + 1}月至${end.getMonth() + 1}月`

  if (statsType.value === 'invest') {
    const totalPnL = investments.value.reduce((sum, item) => {
      const qty = Number(item.quantity || 0)
      const current = Number(item.current_price || 0)
      const cost = Number(item.buy_price || item.average_cost || 0)
      const raw = qty * (current - cost)
      const currency = item.currency || 'TWD'
      return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
    }, 0)
    const totalInvestmentsCost = investments.value.reduce((sum, item) => {
      const qty = Number(item.quantity || 0)
      const cost = Number(item.buy_price || item.average_cost || 0)
      const raw = qty * cost
      const currency = item.currency || 'TWD'
      return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
    }, 0)
    
    return {
      title: dynamicTitle,
      desc1: `持倉成本共 ${formatInvestNumber(totalInvestmentsCost)} 元，`,
      desc2: totalPnL === 0 ? '持倉盈虧沒有改變' : `持倉盈虧${totalPnL > 0 ? '獲利' : '虧損'}了 ${formatInvestNumber(Math.abs(totalPnL))} 元`
    }
  } else {
    let monthlyIncome = 0
    let monthlyExpense = 0
    accounts.value.forEach(acc => {
      if (acc.auto_record) {
        let records = []
        if (Array.isArray(acc.auto_record)) {
          records = acc.auto_record
        } else if (acc.auto_record.enabled) {
          records = [acc.auto_record]
        }
        records.forEach(ar => {
          if (ar.enabled) {
            // Expiry check
            if (ar.expiry === 'custom' && ar.expiry_date) {
              const expDate = new Date(ar.expiry_date + 'T23:59:59')
              if (new Date() > expDate) return
            }
            // Creation check (若本月的記帳日早於創建時間，代表本月不執行，不計入本月圖表)
            if (ar.created_at) {
              const today = new Date()
              const scheduledDate = new Date(today.getFullYear(), today.getMonth(), Number(ar.day || 1))
              if (new Date(ar.created_at) > scheduledDate) return
            }
            const arCurrency = ar.currency || 'TWD'
            let amtTwd = Number(ar.amount || 0)
            if (arCurrency === 'USD') {
              amtTwd = amtTwd * usdTwdRate.value
            } else if (arCurrency === 'JPY') {
              amtTwd = amtTwd * (jpyTwdRate.value || 0.22)
            }
            
            if (ar.type === 'income') {
              monthlyIncome += amtTwd
            } else if (ar.type === 'expense' || ar.type === 'dca_invest') {
              monthlyExpense += amtTwd
            }
          }
        })
      }
    })
    
    return {
      title: dynamicTitle,
      desc1: `預估月收入共 ${formatInvestNumber(Math.round(monthlyIncome))} 元，`,
      desc2: monthlyExpense === 0 ? '預估月支出沒有改變' : `預估月支出共 ${formatInvestNumber(Math.round(monthlyExpense))} 元`
    }
  }
})

const statsChartOptions = computed(() => {
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false
      },
      tooltip: {
        callbacks: {
          label: (context) => {
            return ` ${context.dataset.label}: ${formatInvestNumber(context.raw)} 元`
          }
        }
      }
    },
    scales: {
      x: {
        grid: {
          display: false
        },
        ticks: {
          color: 'var(--color-text-muted)',
          font: {
            size: 11,
            weight: 'bold'
          }
        }
      },
      y: {
        grid: {
          color: 'rgba(0, 0, 0, 0.04)'
        },
        ticks: {
          color: 'var(--color-text-muted)',
          font: {
            size: 11
          },
          callback: (value) => {
            if (value >= 1000000) return (value / 1000000) + 'M'
            if (value >= 1000) return (value / 1000) + 'k'
            return value
          }
        }
      }
    }
  }
})

const accounts = ref([])
const investments = ref([])
const historyRecords = ref([])
const usdTwdRate = ref(32)
const jpyTwdRate = ref(0.21)
const isCurrencyColumnSupported = ref(false)
const isInitialDataLoaded = ref(false)
const isHidden = ref(true)
const isRefreshing = ref(false)
const isSyncingData = ref(false)
const verifyingSymbol = ref(false)
const verificationResult = ref(null)

// 複數自動記帳狀態
const newAssetAutoRecords = ref([])
const activeAutoRecord = ref(null)
const activeAutoRecordIndex = ref(null)

const showDeleteConfirm = ref(false)
const deleteConfirmMessage = ref('')
let deleteCallback = null

const triggerDeleteConfirm = (message, callback) => {
  deleteConfirmMessage.value = message
  deleteCallback = callback
  showDeleteConfirm.value = true
}

const confirmDelete = async () => {
  showDeleteConfirm.value = false
  if (deleteCallback) {
    await deleteCallback()
  }
}

const cancelDelete = () => {
  showDeleteConfirm.value = false
  deleteCallback = null
}

const isTreeView = ref(false)
const hoveredGroup = ref(null)

const listExpanded = ref({
  liquid: false,
  invest: false,
  fixed: false,
  receivable: false,
  liab: false
})
const activeCustomGroup = ref(null)
const activeCustomGroupCategory = ref(null)

const toggleListExpand = (category) => {
  listExpanded.value[category] = !listExpanded.value[category]
}

const filteredAccounts = (category) => {
  const liquidTypes = ['Bank', 'Cash', 'E-Wallet', 'OtherLiquid']
  const fixedTypes = ['RealEstate', 'Car', 'OtherFixed', 'Other']
  const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
  
  if (category === 'liquid') {
    return accounts.value.filter(a => liquidTypes.includes(a.type))
  }
  if (category === 'fixed') {
    return accounts.value.filter(a => fixedTypes.includes(a.type))
  }
  if (category === 'receivable') {
    return accounts.value.filter(a => a.type === 'Receivable')
  }
  if (category === 'liab') {
    return accounts.value.filter(a => liabTypes.includes(a.type))
  }
  return []
}

const investSubtitle = computed(() => {
  const symbols = groupedInvestments.value.map(g => g.symbol)
  return symbols.length > 0 ? symbols.join('、') : '無投資項目'
})

const liquidPct = computed(() => {
  if (totalPositiveAssets.value === 0) return 0
  return Math.round((totalLiquidAssets.value / totalPositiveAssets.value) * 100)
})
const investPct = computed(() => {
  if (totalPositiveAssets.value === 0) return 0
  return Math.round((totalInvestments.value / totalPositiveAssets.value) * 100)
})
const fixedPct = computed(() => {
  if (totalPositiveAssets.value === 0) return 0
  return Math.round((totalFixedAssets.value / totalPositiveAssets.value) * 100)
})
const receivablePct = computed(() => {
  if (totalPositiveAssets.value === 0) return 0
  return Math.round((totalReceivables.value / totalPositiveAssets.value) * 100)
})
const liabPct = computed(() => {
  if (totalPositiveAssets.value === 0 || totalLiabilities.value === 0) return 0
  const pct = Math.round((totalLiabilities.value / totalPositiveAssets.value) * 100)
  return Math.max(1, pct)
})

const isEditing = ref(false)
const editingId = ref(null)

const getCategoryFromType = (type) => {
  const liquidTypes = ['Bank', 'Cash', 'E-Wallet', 'OtherLiquid']
  const fixedTypes = ['RealEstate', 'Car', 'OtherFixed', 'Other']
  const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
  
  if (liquidTypes.includes(type)) return 'liquid'
  if (fixedTypes.includes(type)) return 'fixed'
  if (liabTypes.includes(type)) return 'liab'
  if (type === 'Receivable') return 'receivable'
  return 'liquid'
}

const editAccount = (acc) => {
  isEditing.value = true
  editingId.value = acc.id
  
  // 載入多個自動記帳紀錄
  if (acc.auto_record) {
    if (Array.isArray(acc.auto_record)) {
      newAssetAutoRecords.value = JSON.parse(JSON.stringify(acc.auto_record))
    } else {
      newAssetAutoRecords.value = [JSON.parse(JSON.stringify(acc.auto_record))]
    }
  } else {
    newAssetAutoRecords.value = []
  }
  
  verificationResult.value = null
  newAsset.value = {
    category: getCategoryFromType(acc.type),
    type: acc.type,
    name: acc.name,
    balance: acc.balance,
    include_in_chart: acc.include_in_chart ?? true,
    remarks: acc.remarks ?? '',
    auto_record: null, // 我們改用 newAssetAutoRecords 來管理列表
    custom_group: acc.custom_group ?? '',
    funding_account_id: null,
    currency: acc.currency || 'TWD'
  }
  
  subListType.value = null
  showAddModal.value = true
  addModalStep.value = 2
}

const editInvestment = (inv) => {
  isEditing.value = true
  editingId.value = inv.id
  verificationResult.value = null
  
  newAsset.value = {
    category: 'invest',
    type: (inv.type && inv.type.startsWith('DCA')) ? 'Stock' : (['Stock', 'Crypto', 'Fund'].includes(inv.type) ? inv.type : 'Stock'),
    name: inv.name || '',
    symbol: inv.symbol || '',
    quantity: inv.quantity || 0,
    buy_price: inv.average_cost || inv.buy_price || 0,
    buy_date: inv.buy_date || new Date().toISOString().split('T')[0],
    custom_group: inv.custom_group ?? '',
    funding_account_id: inv.funding_account_id || null,
    include_in_chart: inv.include_in_chart !== false
  }
  
  subListType.value = null
  showAddModal.value = true
  addModalStep.value = 2
}

const editInvestmentBySymbol = (symbol) => {
  const inv = investments.value.find(i => i.symbol.toUpperCase() === symbol.toUpperCase())
  if (inv) {
    editInvestment(inv)
  }
}

const editSnapshotAmount = async (rec) => {
  const newAmtStr = prompt(`請輸入 ${rec.date} 的新淨值金額：`, rec.amount)
  if (newAmtStr === null) return
  const newAmt = Number(newAmtStr)
  if (isNaN(newAmt)) {
    alert('請輸入有效的數字')
    return
  }
  
  // 1. 更新本機 state
  const found = historyRecords.value.find(h => h.date === rec.date)
  if (found) {
    found.amount = newAmt
  }
  
  // 2. 更新 localStorage
  const localHistory = JSON.parse(localStorage.getItem('net_worth_history') || '[]')
  const localFound = localHistory.find(h => h.date === rec.date)
  if (localFound) {
    localFound.amount = newAmt
    localStorage.setItem('net_worth_history', JSON.stringify(localHistory))
  }
  
  // 3. 更新 Supabase
  try {
    const { error } = await supabase
      .from('net_worth_history')
      .update({ amount: newAmt })
      .eq('date', rec.date)
    if (error) {
      console.warn('Update historical snapshot in DB failed:', error)
    } else {
      showToast(`${rec.date} 快照金額已修改為 ${formatInvestNumber(newAmt)} 元`)
    }
  } catch (err) {
    console.warn(err)
  }
}

const deleteSnapshot = (date) => {
  triggerDeleteConfirm(`確定要刪除 ${date} 的歷史快照嗎？此操作將使圖表在該天產生平滑過渡。`, async () => {
    // 1. 更新本機 state
    historyRecords.value = historyRecords.value.filter(h => h.date !== date)
    
    // 2. 更新 localStorage
    const localHistory = JSON.parse(localStorage.getItem('net_worth_history') || '[]')
    const updatedLocal = localHistory.filter(h => h.date !== date)
    localStorage.setItem('net_worth_history', JSON.stringify(updatedLocal))
    
    // 3. 更新 Supabase
    try {
      const { error } = await supabase
        .from('net_worth_history')
        .delete()
        .eq('date', date)
      if (error) {
        console.warn('Delete historical snapshot from DB failed:', error)
      } else {
        showToast(`${date} 歷史快照已成功刪除`)
      }
    } catch (err) {
      console.warn(err)
    }
  })
}

const handleTagInput = (e) => {
  let val = e.target.value
  if (!activeAutoRecord.value) return
  if (val && !val.startsWith('#')) {
    activeAutoRecord.value.tag = '#' + val
  } else {
    activeAutoRecord.value.tag = val
  }
}

const isLiabilityAccount = (accountId) => {
  if (!accountId) return false
  const acc = accounts.value.find(a => a.id === accountId)
  if (!acc) return false
  const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
  return liabTypes.includes(acc.type)
}

const subListType = ref(null)
const toastMessage = ref('')
const showToast = (msg) => {
  toastMessage.value = msg
  setTimeout(() => {
    toastMessage.value = ''
  }, 4000)
}

const autoRecordBackup = ref(null)

const openAddAutoRecord = () => {
  saveError.value = ''
  activeAutoRecord.value = {
    enabled: true, 
    type: 'expense',
    amount: '',
    day: 1,
    tag: '',
    expiry: 'forever',
    expiry_date: new Date(new Date().setMonth(new Date().getMonth() + 12)).toISOString().split('T')[0],
    last_processed_date: null,
    target_account_id: null,
    interest_rate: '',
    symbol: '',
    currency: 'TWD',
    created_at: new Date().toISOString()
  }
  activeAutoRecordIndex.value = null
  addModalStep.value = 3
}

const openEditAutoRecord = (idx) => {
  saveError.value = ''
  activeAutoRecord.value = JSON.parse(JSON.stringify(newAssetAutoRecords.value[idx]))
  activeAutoRecordIndex.value = idx
  addModalStep.value = 3
}

const cancelAutoRecordConfig = () => {
  saveError.value = ''
  activeAutoRecord.value = null
  activeAutoRecordIndex.value = null
  addModalStep.value = 2
}

const saveAutoRecordConfig = async () => {
  if (!activeAutoRecord.value) return
  if (activeAutoRecord.value.amount === '' || activeAutoRecord.value.amount === null) {
    saveError.value = '請輸入金額'
    return
  }
  if (activeAutoRecord.value.type === 'transfer' && !activeAutoRecord.value.target_account_id) {
    saveError.value = '請選擇轉入目標帳戶'
    return
  }
  if (activeAutoRecord.value.type === 'dca_invest' && !activeAutoRecord.value.symbol) {
    saveError.value = '請輸入股票代號'
    return
  }
  if (activeAutoRecord.value.type === 'dca_invest') {
    activeAutoRecord.value.symbol = activeAutoRecord.value.symbol.toUpperCase().trim()
  }
  
  if (activeAutoRecordIndex.value !== null) {
    newAssetAutoRecords.value[activeAutoRecordIndex.value] = { ...activeAutoRecord.value }
  } else {
    // 若為新增且扣款日期已過，則標記本月已執行過，避免儲存後當天立刻被同步扣款
    const today = new Date()
    if (!activeAutoRecord.value.created_at) {
      activeAutoRecord.value.created_at = today.toISOString()
    }
    if (Number(activeAutoRecord.value.day || 1) <= today.getDate()) {
      activeAutoRecord.value.last_processed_date = today.toISOString()
    }
    newAssetAutoRecords.value.push({ ...activeAutoRecord.value })
  }
  
  // 若為編輯現有帳戶，直接同步至資料庫
  if (isEditing.value && editingId.value) {
    const acc = accounts.value.find(a => a.id === editingId.value)
    if (acc) {
      acc.auto_record = newAssetAutoRecords.value.length > 0 ? JSON.parse(JSON.stringify(newAssetAutoRecords.value)) : null
      try {
        await supabase.from('accounts').update({ auto_record: acc.auto_record }).eq('id', editingId.value)
      } catch (dbErr) {
        console.warn('Sync auto_record after configuration failed:', dbErr)
      }
      localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
    }
  }
  
  saveError.value = ''
  activeAutoRecord.value = null
  activeAutoRecordIndex.value = null
  addModalStep.value = 2
  showToast('自動記帳已儲存')
}

const deleteAutoRecord = (idx) => {
  triggerDeleteConfirm('確定要刪除此自動記帳設定嗎？此動作將立即儲存。', async () => {
    newAssetAutoRecords.value.splice(idx, 1)
    
    if (isEditing.value && editingId.value) {
      const acc = accounts.value.find(a => a.id === editingId.value)
      if (acc) {
        acc.auto_record = newAssetAutoRecords.value.length > 0 ? JSON.parse(JSON.stringify(newAssetAutoRecords.value)) : null
        
        try {
          await supabase.from('accounts').update({ auto_record: acc.auto_record }).eq('id', editingId.value)
        } catch (dbErr) {
          console.warn('Sync auto_record after deletion failed:', dbErr)
        }
        
        localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
      }
    }
    showToast('自動記帳已刪除')
  })
}

const nextRecordDateStr = computed(() => {
  if (!activeAutoRecord.value) return ''
  const today = new Date()
  let targetMonth = today.getMonth()
  let targetYear = today.getFullYear()
  const day = Number(activeAutoRecord.value.day || 1)
  
  if (today.getDate() >= day) {
    targetMonth++
    if (targetMonth > 11) {
      targetMonth = 0
      targetYear++
    }
  }
  return `${targetMonth + 1}月${day}日`
})

const autoRecordsSummary = computed(() => {
  let incomeTwd = 0
  let expenseTwd = 0
  newAssetAutoRecords.value.forEach(ar => {
    const amt = Number(ar.amount || 0)
    const currency = ar.currency || 'TWD'
    let amtTwd = amt
    if (currency === 'USD') {
      amtTwd = amt * usdTwdRate.value
    } else if (currency === 'JPY') {
      amtTwd = amt * (jpyTwdRate.value || 0.22)
    }
    
    if (ar.type === 'income') {
      incomeTwd += amtTwd
    } else {
      expenseTwd += amtTwd
    }
  })
  return {
    income: 'TWD ' + Math.round(incomeTwd).toLocaleString('en-US'),
    expense: 'TWD ' + Math.round(expenseTwd).toLocaleString('en-US')
  }
})

const getNextTxDateStr = (day) => {
  const today = new Date()
  let m = today.getMonth() + 1
  let y = today.getFullYear()
  if (today.getDate() >= Number(day)) {
    m++
    if (m > 12) {
      m = 1
      y++
    }
  }
  return `${m}月${day}日`
}

// 新增項目 Modal
const showAddModal = ref(false)
const showFlowAnalysisModal = ref(false)
const addModalStep = ref(1) // 1 = 選擇類別, 2 = 填寫表單
const expandedCategories = ref({
  liquid: true,
  invest: false,
  fixed: false,
  receivable: false,
  liab: false
})
const isSaving = ref(false)
const saveError = ref('')
const newAsset = ref({
  category: 'liquid', // liquid, invest, fixed, receivable, liab
  type: 'Bank',       // Bank, Cash, E-Wallet, OtherLiquid, Fund, Stock, Crypto, Metal, OtherInvest, RealEstate, Car, OtherFixed, Receivable, Credit Card, Loan, Payable, OtherLiab
  name: '',
  balance: '',
  symbol: '',
  quantity: '',
  buy_price: '',
  buy_date: new Date().toISOString().split('T')[0],
  custom_group: '',
  funding_account_id: null
})

// 折線圖時間篩選
const timeFilter = ref('6M') // 1M, 3M, 6M, ALL

const selectedSymbol = ref('')
const selectedInvestment = computed(() => {
  const symbol = selectedSymbol.value.toUpperCase()
  if (!symbol) return null
  const matching = investments.value.filter(i => i.symbol.toUpperCase() === symbol)
  if (matching.length === 0) return null
  
  const name = matching[0].name || symbol
  const currency = matching[0].currency || (isTaiwanStock(symbol) ? 'TWD' : 'USD')
  const type = matching[0].asset_class || matching[0].type || 'Stock'
  const current_price = matching[0].current_price || 0
  const qty = matching.reduce((sum, item) => sum + Number(item.quantity || 0), 0)
  const totalVal = qty * current_price
  const totalValTwd = currency === 'USD' ? totalVal * usdTwdRate.value : totalVal
  
  return {
    symbol,
    name,
    currency,
    type,
    current_price,
    quantity: qty,
    value: totalVal,
    valueTwd: totalValTwd,
    lots: [...matching].sort((a, b) => new Date(b.buy_date || b.created_at) - new Date(a.buy_date || a.created_at))
  }
})

const openInvestmentDetail = (symbol) => {
  selectedSymbol.value = symbol.toUpperCase()
  showAddModal.value = true
  addModalStep.value = 4
}

const adjustSharesVal = ref('')
const adjustAction = ref('plus')
const adjustPrice = ref(0)
const customProfitVal = ref('')
const adjustRemarks = ref('增減金額')
const modifySharesVal = ref('')
const modifyPrice = ref(0)
const modifyRemarks = ref('修改餘額')

const openAdjustShares = () => {
  const inv = selectedInvestment.value
  if (!inv) return
  adjustSharesVal.value = ''
  adjustAction.value = 'plus'
  adjustPrice.value = inv.current_price
  customProfitVal.value = ''
  adjustRemarks.value = '增減金額'
  addModalStep.value = 5 // Step 5: Adjust Shares
}

const openModifyBalance = () => {
  const inv = selectedInvestment.value
  if (!inv) return
  modifySharesVal.value = inv.quantity
  modifyPrice.value = inv.current_price
  modifyRemarks.value = '修改餘額'
  addModalStep.value = 6 // Step 6: Modify Balance
}

const submitAdjustShares = async () => {
  const inv = selectedInvestment.value
  if (!inv) return
  const qtyChange = Number(adjustSharesVal.value || 0)
  if (qtyChange <= 0) return
  
  const finalQtyChange = adjustAction.value === 'plus' ? qtyChange : -qtyChange
  const buyPrice = Number(adjustPrice.value || 0)
  
  const lots = investments.value.filter(i => i.symbol.toUpperCase() === inv.symbol.toUpperCase())
  if (lots.length > 0) {
    // ── Funding/Proceeds account updates ──
    let accountsChanged = false
    let updatedAccounts = [...accounts.value]
    
    if (newAsset.value.funding_account_id && syncAccountBalance.value) {
      const lotCurrency = lots[0].currency || 'TWD'
      const txVal = qtyChange * buyPrice
      const txValTwd = lotCurrency === 'USD' ? txVal * usdTwdRate.value : txVal
      
      updatedAccounts = updatedAccounts.map(acc => {
        if (acc.id === newAsset.value.funding_account_id) {
          if (adjustAction.value === 'plus') {
            adjustAccountBalanceByTwd(acc, -txValTwd)
            if (acc.balance < 0) acc.balance = 0
          } else {
            adjustAccountBalanceByTwd(acc, txValTwd)
          }
          acc._dirty = true
          accountsChanged = true
        }
        return acc
      })
    }

    if (finalQtyChange > 0) {
      if (newAsset.value.funding_account_id) {
        todayTransactions.value.push({
          type: 'buy',
          symbol: inv.symbol.toUpperCase(),
          quantity: finalQtyChange,
          price: buyPrice,
          currency: lots[0].currency || 'TWD',
          funding_account_id: newAsset.value.funding_account_id,
          date: new Date().toISOString().split('T')[0]
        })
      }
      const generatedId = 'local-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9)
      const nowStr = new Date().toISOString()
      const payload = {
        id: generatedId,
        asset_class: lots[0].asset_class,
        symbol: inv.symbol.toUpperCase(),
        name: inv.name,
        quantity: finalQtyChange,
        average_cost: buyPrice,
        currency: lots[0].currency,
        type: 'Stock',
        current_price: buyPrice,
        buy_price: buyPrice,
        buy_date: new Date().toISOString().split('T')[0],
        created_at: nowStr,
        price_updated_at: nowStr,
        custom_group: lots[0].custom_group || '',
        funding_account_id: newAsset.value.funding_account_id || null
      }
      try {
        const dbPayload = { ...payload }
        delete dbPayload.id
        const { data, error } = await supabase.from('investments').insert([dbPayload]).select()
        if (!error && data) {
          payload.id = data[0].id
        }
      } catch {}
      investments.value.unshift(payload)
    } else {
      let remainingToSubtract = Math.abs(finalQtyChange)
      let customProfitAssigned = false
      for (let i = 0; i < lots.length; i++) {
        const lot = lots[i]
        if (lot.quantity >= remainingToSubtract) {
          const qtySubtracted = remainingToSubtract
          let profit = 0
          if (customProfitVal.value !== '') {
            if (!customProfitAssigned) {
              profit = Number(customProfitVal.value)
              customProfitAssigned = true
            } else {
              profit = 0
            }
          } else {
            profit = (buyPrice - Number(lot.average_cost || 0)) * qtySubtracted
          }
          
          if (newAsset.value.funding_account_id) {
            todayTransactions.value.push({
              type: 'sell',
              symbol: inv.symbol.toUpperCase(),
              quantity: qtySubtracted,
              price: buyPrice,
              average_cost: Number(lot.average_cost || 0),
              currency: lot.currency || 'TWD',
              funding_account_id: newAsset.value.funding_account_id,
              date: new Date().toISOString().split('T')[0],
              profit: profit
            })
          }
          lot.quantity -= remainingToSubtract
          remainingToSubtract = 0
          try {
            await supabase.from('investments').update({ quantity: lot.quantity }).eq('id', lot.id)
          } catch {}
          break;
        } else {
          const qtySubtracted = lot.quantity
          let profit = 0
          if (customProfitVal.value !== '') {
            if (!customProfitAssigned) {
              profit = Number(customProfitVal.value)
              customProfitAssigned = true
            } else {
              profit = 0
            }
          } else {
            profit = (buyPrice - Number(lot.average_cost || 0)) * qtySubtracted
          }

          if (newAsset.value.funding_account_id) {
            todayTransactions.value.push({
              type: 'sell',
              symbol: inv.symbol.toUpperCase(),
              quantity: qtySubtracted,
              price: buyPrice,
              average_cost: Number(lot.average_cost || 0),
              currency: lot.currency || 'TWD',
              funding_account_id: newAsset.value.funding_account_id,
              date: new Date().toISOString().split('T')[0],
              profit: profit
            })
          }
          remainingToSubtract -= lot.quantity
          lot.quantity = 0
          try {
            await supabase.from('investments').update({ quantity: 0 }).eq('id', lot.id)
          } catch {}
        }
      }
      investments.value = investments.value.filter(i => i.quantity > 0)
    }
    localStorage.setItem('local_investments', JSON.stringify(investments.value))

    // Save accounts changes if any funding occurred
    if (accountsChanged) {
      accounts.value = updatedAccounts
      const cleanAccounts = updatedAccounts.map(a => {
        const copy = { ...a }
        delete copy._dirty
        return copy
      })
      localStorage.setItem('local_accounts', JSON.stringify(cleanAccounts))
      for (const acc of updatedAccounts) {
        if (acc._dirty) {
          delete acc._dirty
          try {
            await supabase.from('accounts').update({ balance: acc.balance }).eq('id', acc.id)
          } catch (err) {
            console.warn('Sync account balance after investment adjustment failed:', err)
          }
        }
      }
    }
  }
  
  await saveDailySnapshot(netWorth.value)
  await fetchAllData()
  addModalStep.value = 4
}

const submitModifyBalance = async () => {
  const inv = selectedInvestment.value
  if (!inv) return
  const newQty = Number(modifySharesVal.value || 0)
  const buyPrice = Number(modifyPrice.value || 0)
  
  const lots = investments.value.filter(i => i.symbol.toUpperCase() === inv.symbol.toUpperCase())
  if (lots.length > 0) {
    const firstLot = lots[0]
    const oldQty = Number(firstLot.quantity || 0)
    const oldPrice = Number(firstLot.buy_price || firstLot.average_cost || 0)
    
    // No longer adjusting funding account balance to avoid double deduction
    
    firstLot.quantity = newQty
    firstLot.average_cost = buyPrice
    firstLot.current_price = buyPrice
    firstLot.buy_price = buyPrice
    
    try {
      await supabase.from('investments').update({ quantity: newQty, average_cost: buyPrice, current_price: buyPrice, buy_price: buyPrice }).eq('id', firstLot.id)
      for (let i = 1; i < lots.length; i++) {
        await supabase.from('investments').delete().eq('id', lots[i].id)
      }
    } catch {}
    
    investments.value = investments.value.filter(i => i.symbol.toUpperCase() !== inv.symbol.toUpperCase() || i.id === firstLot.id)
    const localIdx = investments.value.findIndex(i => i.id === firstLot.id)
    if (localIdx !== -1) {
      investments.value[localIdx].quantity = newQty
      investments.value[localIdx].average_cost = buyPrice
      investments.value[localIdx].current_price = buyPrice
      investments.value[localIdx].buy_price = buyPrice
    }
    
    localStorage.setItem('local_investments', JSON.stringify(investments.value))
  }
  
  await fetchAllData()
  addModalStep.value = 4
}

// ── Calculations ──────────────────────────────────────────────────
// 1. 流動資金 (Bank / Cash / E-Wallet / OtherLiquid)
const totalLiquidAssets = computed(() => {
  const liquidTypes = ['Bank', 'Cash', 'E-Wallet', 'OtherLiquid']
  return accounts.value
    .filter(a => liquidTypes.includes(a.type) && a.include_in_chart !== false)
    .reduce((sum, acc) => sum + getAccountBalanceTwd(acc), 0)
})

// 2. 投資部位市值
const totalInvestments = computed(() => {
  return investments.value.reduce((sum, item) => {
    if (item.include_in_chart === false) return sum
    const qty = Number(item.quantity || 0)
    const price = Number(item.current_price || 0)
    const raw = qty * price
    const currency = item.currency || (item.asset_class === 'us_stock' ? 'USD' : 'TWD')
    return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
  }, 0)
})

// 3. 固定資產 (RealEstate / Car / OtherFixed)
const totalFixedAssets = computed(() => {
  const fixedTypes = ['RealEstate', 'Car', 'OtherFixed', 'Other'] // Include fallback type 'Other'
  return accounts.value
    .filter(a => fixedTypes.includes(a.type) && a.include_in_chart !== false)
    .reduce((sum, acc) => sum + getAccountBalanceTwd(acc), 0)
})

// 4. 應收款項目 (Receivable)
const totalReceivables = computed(() => {
  return accounts.value
    .filter(a => a.type === 'Receivable' && a.include_in_chart !== false)
    .reduce((sum, acc) => sum + getAccountBalanceTwd(acc), 0)
})

// 5. 負債項目 (Liability / Credit Card / Loan / Payable / OtherLiab)
const totalLiabilities = computed(() => {
  const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
  return accounts.value
    .filter(a => liabTypes.includes(a.type) && a.include_in_chart !== false)
    .reduce((sum, acc) => sum + getAccountBalanceTwd(acc), 0)
})

// 6. 總淨資產 = 流動資金 + 投資部位 + 固定資產 + 應收款 - 負債
const netWorth = computed(() => {
  return totalLiquidAssets.value + totalInvestments.value + totalFixedAssets.value + totalReceivables.value - totalLiabilities.value
})

// 左側垂直佔比條比例計算 (僅計算正資產)
const totalPositiveAssets = computed(() => {
  return totalLiquidAssets.value + totalInvestments.value + totalFixedAssets.value + totalReceivables.value
})
const liquidBarPct = computed(() => {
  if (totalPositiveAssets.value === 0) return 0
  return (totalLiquidAssets.value / totalPositiveAssets.value) * 100
})
const investBarPct = computed(() => {
  if (totalPositiveAssets.value === 0) return 0
  return (totalInvestments.value / totalPositiveAssets.value) * 100
})
const fixedBarPct = computed(() => {
  if (totalPositiveAssets.value === 0) return 0
  return (totalFixedAssets.value / totalPositiveAssets.value) * 100
})
const receivableBarPct = computed(() => {
  if (totalPositiveAssets.value === 0) return 0
  return (totalReceivables.value / totalPositiveAssets.value) * 100
})

// 卡片副標題文字串接
const liquidSubtitle = computed(() => {
  const liquidTypes = ['Bank', 'Cash', 'E-Wallet', 'OtherLiquid']
  const matched = accounts.value.filter(a => liquidTypes.includes(a.type))
  return matched.length > 0 ? matched.map(a => a.name).join('、') : '無帳戶'
})
const fixedSubtitle = computed(() => {
  const fixedTypes = ['RealEstate', 'Car', 'OtherFixed', 'Other']
  const matched = accounts.value.filter(a => fixedTypes.includes(a.type))
  return matched.length > 0 ? matched.map(a => a.name).join('、') : '無固定資產'
})
const receivableSubtitle = computed(() => {
  const matched = accounts.value.filter(a => a.type === 'Receivable')
  return matched.length > 0 ? matched.map(a => a.name).join('、') : '無應收款項'
})
const liabSubtitle = computed(() => {
  const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
  const matched = accounts.value.filter(a => liabTypes.includes(a.type))
  return matched.length > 0 ? matched.map(a => a.name).join('、') : '無負債'
})

// 投資標的合併與佔總投資百分比計算
const groupedInvestments = computed(() => {
  const groups = {}
  
  investments.value.forEach(inv => {
    const sym = inv.symbol.toUpperCase()
    if (!groups[sym]) {
      groups[sym] = {
        symbol: sym,
        name: inv.name || sym,
        currency: inv.currency || 'TWD',
        current_price: Number(inv.current_price || 0),
        qty: 0,
        costTwd: 0,
        price_updated_at: inv.price_updated_at,
        custom_group: inv.custom_group || ''
      }
    }
    const qty = Number(inv.quantity || 0)
    groups[sym].qty += qty
    
    // 計算該筆投資的台幣成本
    const buyPrice = Number(inv.buy_price || inv.average_cost || 0)
    const lotCost = qty * buyPrice
    const lotCostTwd = (inv.currency || 'TWD') === 'USD' ? lotCost * usdTwdRate.value : lotCost
    groups[sym].costTwd += lotCostTwd
    
    if (inv.price_updated_at && (!groups[sym].price_updated_at || inv.price_updated_at > groups[sym].price_updated_at)) {
      groups[sym].price_updated_at = inv.price_updated_at
      groups[sym].current_price = Number(inv.current_price || 0)
    }
  })

  return Object.values(groups).map(g => {
    const rawVal = g.qty * g.current_price
    const valTwd = g.currency === 'USD' ? rawVal * usdTwdRate.value : rawVal
    const pct = totalInvestments.value > 0 ? (valTwd / totalInvestments.value) * 100 : 0
    const pnl = valTwd - g.costTwd
    const pnlPct = g.costTwd > 0 ? (pnl / g.costTwd) * 100 : 0
    return {
      ...g,
      valueTwd: valTwd,
      percentage: pct,
      pnl,
      pnlPct
    }
  }).sort((a, b) => b.valueTwd - a.valueTwd)
})

// 計算投資部位總成本與投報率
const totalInvestmentCostTwd = computed(() => {
  return investments.value.reduce((sum, item) => {
    if (item.include_in_chart === false) return sum
    const qty = Number(item.quantity || 0)
    const cost = Number(item.buy_price || item.average_cost || 0)
    const raw = qty * cost
    const currency = item.currency || (item.asset_class === 'us_stock' ? 'USD' : 'TWD')
    return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
  }, 0)
})

const totalInvestmentPnL = computed(() => {
  return totalInvestments.value - totalInvestmentCostTwd.value
})

const totalInvestmentPnLPct = computed(() => {
  return totalInvestmentCostTwd.value > 0 ? (totalInvestmentPnL.value / totalInvestmentCostTwd.value) * 100 : 0
})

// 提取目前所有已建立的群組
const existingGroups = computed(() => {
  const groups = new Set()
  if (Array.isArray(accounts.value)) {
    accounts.value.forEach(acc => {
      if (acc.custom_group && acc.custom_group.trim()) {
        groups.add(acc.custom_group.trim())
      }
    })
  }
  if (Array.isArray(investments.value)) {
    investments.value.forEach(inv => {
      if (inv.custom_group && inv.custom_group.trim()) {
        groups.add(inv.custom_group.trim())
      }
    })
  }
  return Array.from(groups)
})

// 依自訂群組分組資產
const groupAccountsByCustomGroup = (category) => {
  const list = filteredAccounts(category)
  const grouped = {}
  list.forEach(acc => {
    const g = acc.custom_group ? acc.custom_group.trim() : ''
    if (!grouped[g]) grouped[g] = []
    grouped[g].push(acc)
  })
  const result = []
  Object.keys(grouped).forEach(k => {
    if (k !== '') {
      result.push({ name: k, items: grouped[k] })
    }
  })
  result.sort((a, b) => a.name.localeCompare(b.name))
  if (grouped[''] && grouped[''].length > 0) {
    result.unshift({ name: '', items: grouped[''] })
  }
  return result
}

// 依自訂群組分組投資
const groupedInvestmentsByCustomGroup = computed(() => {
  const list = groupedInvestments.value
  const grouped = {}
  list.forEach(inv => {
    const g = inv.custom_group ? inv.custom_group.trim() : ''
    if (!grouped[g]) grouped[g] = []
    grouped[g].push(inv)
  })
  
  const result = []
  Object.keys(grouped).forEach(k => {
    const items = grouped[k]
    const groupTotalValTwd = items.reduce((sum, item) => sum + item.valueTwd, 0)
    const groupPct = totalInvestments.value > 0 ? (groupTotalValTwd / totalInvestments.value) * 100 : 0
    
    const itemsWithGroupPct = items.map(item => {
      const itemGroupPct = groupTotalValTwd > 0 ? (item.valueTwd / groupTotalValTwd) * 100 : 0
      return {
        ...item,
        groupPercentage: itemGroupPct
      }
    }).sort((a, b) => b.valueTwd - a.valueTwd)
    
    if (k !== '') {
      result.push({ name: k, totalValueTwd: groupTotalValTwd, percentage: groupPct, items: itemsWithGroupPct })
    } else {
      result.push({ name: '未分類', totalValueTwd: groupTotalValTwd, percentage: groupPct, items: itemsWithGroupPct, isUnclassified: true })
    }
  })
  
  const namedGroups = result.filter(r => !r.isUnclassified).sort((a, b) => a.name.localeCompare(b.name))
  const unclassified = result.find(r => r.isUnclassified)
  
  if (unclassified && unclassified.items.length > 0) {
    namedGroups.push(unclassified)
  }
  return namedGroups
})

const investListItems = computed(() => {
  const result = []
  groupedInvestmentsByCustomGroup.value.forEach(g => {
    if (!g.isUnclassified && g.name !== '未分類') {
      const groupPnl = g.items.reduce((sum, i) => sum + (i.pnl || 0), 0)
      const groupCost = g.items.reduce((sum, i) => sum + (i.costTwd || 0), 0)
      const groupPnlPct = groupCost > 0 ? (groupPnl / groupCost) * 100 : 0
      result.push({
        isGroup: true,
        name: g.name,
        percentage: g.percentage,
        valueTwd: g.totalValueTwd,
        items: g.items,
        desc: g.items.map(i => i.name || i.symbol).join('、'),
        price_updated_at: g.items[0]?.price_updated_at,
        pnl: groupPnl,
        pnlPct: groupPnlPct
      })
    } else {
      g.items.forEach(item => {
        const itemPct = totalInvestments.value > 0 ? (item.valueTwd / totalInvestments.value) * 100 : 0
        const formattedQty = Number(Number(item.qty || 0).toFixed(4))
        result.push({
          isGroup: false,
          name: item.name,
          symbol: item.symbol,
          percentage: itemPct,
          valueTwd: item.valueTwd,
          formattedQty,
          currency: item.currency || 'TWD',
          current_price: item.current_price || 0,
          price_updated_at: item.price_updated_at,
          pnl: item.pnl,
          pnlPct: item.pnlPct,
          rawItem: item
        })
      })
    }
  })
  return result.sort((a, b) => b.valueTwd - a.valueTwd)
})

const activeGroupItems = computed(() => {
  if (!activeCustomGroup.value || !activeCustomGroupCategory.value) return []
  if (activeCustomGroupCategory.value === 'invest') {
    const group = groupedInvestmentsByCustomGroup.value.find(g => g.name === activeCustomGroup.value)
    return group ? group.items : []
  } else {
    const grouped = groupAccountsByCustomGroup(activeCustomGroupCategory.value)
    const group = grouped.find(g => g.name === activeCustomGroup.value)
    if (!group) return []
    const groupTotal = group.items.reduce((sum, item) => sum + item.balance, 0)
    return group.items.map(item => {
      const itemGroupPct = groupTotal > 0 ? (item.balance / groupTotal) * 100 : 0
      return {
        ...item,
        groupPercentage: itemGroupPct
      }
    }).sort((a, b) => b.balance - a.balance)
  }
})

const activeCustomGroupPnL = computed(() => {
  if (!activeCustomGroup.value || activeCustomGroupCategory.value !== 'invest') return 0
  return activeGroupItems.value.reduce((sum, item) => sum + (item.pnl || 0), 0)
})

const activeCustomGroupPnLPct = computed(() => {
  if (!activeCustomGroup.value || activeCustomGroupCategory.value !== 'invest') return 0
  const cost = activeGroupItems.value.reduce((sum, item) => sum + (item.costTwd || 0), 0)
  return cost > 0 ? (activeCustomGroupPnL.value / cost) * 100 : 0
})

const openCustomGroupDetail = (groupName, category) => {
  activeCustomGroup.value = groupName
  activeCustomGroupCategory.value = category
}

const closeCustomGroupDetail = () => {
  activeCustomGroup.value = null
  activeCustomGroupCategory.value = null
}

const getCategoryTotal = (category) => {
  if (category === 'liquid') return totalLiquidAssets.value
  if (category === 'fixed') return totalFixedAssets.value
  if (category === 'receivable') return totalReceivables.value
  if (category === 'liab') return totalLiabilities.value
  return 0
}

function getAccountBalanceTwd(acc) {
  if (!acc) return 0
  const bal = Math.abs(Number(acc.balance || 0))
  const currency = acc.currency || 'TWD'
  const rate = currency === 'USD' ? usdTwdRate.value : (currency === 'JPY' ? jpyTwdRate.value : 1)
  return Math.round(bal * rate)
}

function adjustAccountBalanceByTwd(acc, amountTwd) {
  if (!acc) return
  const currency = acc.currency || 'TWD'
  const rate = currency === 'USD' ? usdTwdRate.value : (currency === 'JPY' ? jpyTwdRate.value : 1)
  const amtInAccCurrency = amountTwd / rate
  const currentBal = Number(acc.balance || 0)
  acc.balance = Math.round(currentBal + amtInAccCurrency)
}

const getCategoryFlatList = (category) => {
  const result = []
  const grouped = groupAccountsByCustomGroup(category)
  const catTotal = getCategoryTotal(category)
  
  grouped.forEach(g => {
    if (g.name !== '') {
      const groupTotal = g.items.reduce((sum, item) => sum + getAccountBalanceTwd(item), 0)
      const pct = catTotal > 0 ? (groupTotal / catTotal) * 100 : 0
      result.push({
        isGroup: true,
        name: g.name,
        category,
        percentage: pct,
        balance: groupTotal,
        desc: g.items.map(item => item.name).join('、'),
        items: g.items
      })
    } else {
      g.items.forEach(item => {
        const balanceTwd = getAccountBalanceTwd(item)
        const itemPct = catTotal > 0 ? (balanceTwd / catTotal) * 100 : 0
        result.push({
          isGroup: false,
          name: item.name,
          category,
          percentage: itemPct,
          balance: balanceTwd,
          desc: translateTypeSettings(item.type),
          rawItem: item
        })
      })
    }
  })
  
  return result.sort((a, b) => b.balance - a.balance)
}

const addAssetToActiveGroup = () => {
  isEditing.value = false
  newAsset.value = {
    category: 'invest',
    type: 'Stock',
    name: '',
    symbol: '',
    quantity: '',
    buy_price: '',
    buy_date: new Date().toISOString().split('T')[0],
    custom_group: activeCustomGroup.value,
    funding_account_id: null
  }
  showAddModal.value = true
  addModalStep.value = 2
}

const handleCustomGroupChange = (type) => {
  if (newAsset.value.custom_group === '__NEW__') {
    const newName = prompt('請輸入新群組名稱：')
    if (newName && newName.trim()) {
      const trimmed = newName.trim()
      if (type === 'invest') {
        if (!customInvestGroupsList.value.includes(trimmed)) {
          customInvestGroupsList.value.push(trimmed)
          localStorage.setItem('custom_invest_groups', JSON.stringify(customInvestGroupsList.value))
        }
        newAsset.value.custom_group = trimmed
      } else {
        if (!customAccountGroupsList.value.includes(trimmed)) {
          customAccountGroupsList.value.push(trimmed)
          localStorage.setItem('custom_account_groups', JSON.stringify(customAccountGroupsList.value))
        }
        newAsset.value.custom_group = trimmed
      }
    } else {
      newAsset.value.custom_group = ''
    }
  }
}


// 歷史趨勢折線圖篩選
const trendType = ref('net_worth') // net_worth or liquid_invest
const customStartDate = ref(new Date(Date.now() - 180 * 24 * 3600 * 1000).toISOString().split('T')[0])
const customEndDate = ref(new Date().toISOString().split('T')[0])

const filteredHistory = computed(() => {
  if (historyRecords.value.length === 0) return []
  const now = new Date()
  let limitDate = new Date()
  
  if (timeFilter.value === '30D') {
    limitDate.setDate(now.getDate() - 30);
    return historyRecords.value.filter(r => new Date(r.date) >= limitDate);
  } else if (timeFilter.value === '6M') {
    limitDate.setMonth(now.getMonth() - 6);
    return historyRecords.value.filter(r => new Date(r.date) >= limitDate);
  } else if (timeFilter.value === '1Y') {
    limitDate.setFullYear(now.getFullYear() - 1);
    return historyRecords.value.filter(r => new Date(r.date) >= limitDate);
  } else if (timeFilter.value === 'YTD') {
    limitDate = new Date(now.getFullYear(), 0, 1);
    return historyRecords.value.filter(r => new Date(r.date) >= limitDate);
  } else if (timeFilter.value === 'ALL') {
    const start = new Date(customStartDate.value)
    const end = new Date(customEndDate.value)
    end.setHours(23, 59, 59, 999)
    return historyRecords.value.filter(r => {
      const d = new Date(r.date)
      return d >= start && d <= end
    })
  }
  return historyRecords.value
})

// 雙模式走勢數據計算 (結合當前實際比例與歷史淨值，採用固定資產與負債視為常數之優化算法)
const trendDatasets = computed(() => {
  const history = filteredHistory.value
  if (history.length === 0) return []
  
  const todayNetWorth = netWorth.value
  const todayLiabilities = totalLiabilities.value
  const todayLiquid = totalLiquidAssets.value
  const todayInvest = totalInvestments.value
  const todayFixed = totalFixedAssets.value
  const todayReceivables = totalReceivables.value
  
  // 計算流動資金與投資部位之間的分配比例
  const totalLiquidInvest = todayLiquid + todayInvest
  const liquidRatio = totalLiquidInvest > 0 ? todayLiquid / totalLiquidInvest : 0.5
  const investRatio = totalLiquidInvest > 0 ? todayInvest / totalLiquidInvest : 0.5
  
  // 為了效能，在最外層只解析一次不計入圖表的 ID 對照表
  const excludedAccs = JSON.parse(localStorage.getItem('excluded_accounts_ids') || '[]')
  const excludedInvs = JSON.parse(localStorage.getItem('excluded_investments_ids') || '[]')
  
  // 動態根據當前「計入圖表」設定重新計算歷史快照點的淨值
  const getHistoricalAmount = (r) => {
    if (!r.details || !r.details.accounts) {
      return r.amount // 若為老舊無詳細資料快照，則回退使用當時紀錄的值
    }
    
    const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
    let totalAcc = 0
    Object.entries(r.details.accounts).forEach(([id, bal]) => {
      if (!excludedAccs.includes(id)) {
        const acc = accounts.value.find(a => a.id === id)
        const isLiab = acc ? liabTypes.includes(acc.type) : false
        const currency = acc ? (acc.currency || 'TWD') : 'TWD'
        const rate = currency === 'USD' ? usdTwdRate.value : (currency === 'JPY' ? jpyTwdRate.value : 1)
        const balTwd = Number(bal || 0) * rate
        
        if (isLiab) {
          totalAcc -= Math.abs(balTwd)
        } else {
          totalAcc += balTwd
        }
      }
    })
    
    let totalInv = 0
    if (Array.isArray(r.details.investments)) {
      r.details.investments.forEach(inv => {
        if (!excludedInvs.includes(inv.id)) {
          const val = Number(inv.quantity || 0) * Number(inv.current_price || 0)
          const valTwd = inv.currency === 'USD' ? val * usdTwdRate.value : val
          totalInv += valTwd
        }
      })
    } else if (r.details.investments_value !== undefined) {
      totalInv = Number(r.details.investments_value || 0)
    }
    
    return Math.round(totalAcc + totalInv)
  }

  return history.map((r, idx) => {
    // 最後一個節點強制符合當前真實數據
    if (idx === history.length - 1) {
      return {
        date: r.date,
        netWorth: todayNetWorth,
        liabilities: todayLiabilities,
        liquid: todayLiquid,
        invest: todayInvest,
        details: {
          accounts: accounts.value.reduce((acc, curr) => {
            acc[curr.id] = Number(curr.balance)
            return acc
          }, {}),
          investments_value: todayInvest,
          investments_cost: totalInvestmentCostTwd.value
        }
      }
    }
    
    if (r.details && r.details.accounts) {
      const liquidTypes = ['Bank', 'Cash', 'E-Wallet', 'OtherLiquid']
      const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
      const fixedTypes = ['RealEstate', 'Car', 'OtherFixed', 'Other']
      
      let totalLiquidAcc = 0
      let totalLiabilitiesAcc = 0
      let totalFixedAcc = 0
      let totalReceivablesAcc = 0
      
      Object.entries(r.details.accounts).forEach(([id, bal]) => {
        if (!excludedAccs.includes(id)) {
          const acc = accounts.value.find(a => a.id === id)
          const type = acc ? acc.type : 'Other'
          const currency = acc ? (acc.currency || 'TWD') : 'TWD'
          const rate = currency === 'USD' ? usdTwdRate.value : (currency === 'JPY' ? jpyTwdRate.value : 1)
          const balTwd = Number(bal || 0) * rate
          
          if (liabTypes.includes(type)) {
            totalLiabilitiesAcc += Math.abs(balTwd)
          } else if (liquidTypes.includes(type)) {
            totalLiquidAcc += balTwd
          } else if (fixedTypes.includes(type)) {
            totalFixedAcc += balTwd
          } else if (type === 'Receivable') {
            totalReceivablesAcc += balTwd
          } else {
            totalLiquidAcc += balTwd
          }
        }
      })
      
      let totalInv = 0
      if (Array.isArray(r.details.investments)) {
        r.details.investments.forEach(inv => {
          if (!excludedInvs.includes(inv.id)) {
            const val = Number(inv.quantity || 0) * Number(inv.current_price || 0)
            const valTwd = inv.currency === 'USD' ? val * usdTwdRate.value : val
            totalInv += valTwd
          }
        })
      } else if (r.details.investments_value !== undefined) {
        totalInv = Number(r.details.investments_value || 0)
      }
      
      return {
        date: r.date,
        netWorth: Math.round(totalLiquidAcc + totalInv + totalFixedAcc + totalReceivablesAcc - totalLiabilitiesAcc),
        liabilities: Math.round(totalLiabilitiesAcc),
        liquid: Math.round(totalLiquidAcc),
        invest: Math.round(totalInv),
        details: r.details
      }
    }
    
    // 方案 A：對於無明細的舊版快照，才回退使用歷史比例估算
    const rAmount = getHistoricalAmount(r)
    const estLiquidInvest = Math.max(0, rAmount + todayLiabilities - todayFixed - todayReceivables)
    const estLiquid = estLiquidInvest * liquidRatio
    const estInvest = estLiquidInvest * investRatio
    
    return {
      date: r.date,
      netWorth: rAmount,
      liabilities: todayLiabilities,
      liquid: estLiquid,
      invest: estInvest,
      details: r.details
    }
  })
})

const selectedHistoryIndex = ref(null)
const trendSubTab = ref('details')

watch(trendDatasets, (newVal) => {
  if (newVal.length > 0) {
    if (selectedHistoryIndex.value === null || selectedHistoryIndex.value >= newVal.length) {
      selectedHistoryIndex.value = newVal.length - 1
    }
  } else {
    selectedHistoryIndex.value = null
  }
}, { immediate: true })

const selectedHistoryDetails = computed(() => {
  const datasets = trendDatasets.value
  const idx = selectedHistoryIndex.value
  if (idx === null || !datasets[idx]) return null
  
  const current = datasets[idx]
  const prev = idx > 0 ? datasets[idx - 1] : null
  const hasRealPrevDetails = !!(prev && prev.details && prev.details.accounts)
  
  const nwDiff = prev ? current.netWorth - prev.netWorth : 0
  
  const changes = []
  
  const currentAccs = current.details?.accounts || {}
  const prevAccs = prev?.details?.accounts || {}
  
  const excludedAccs = JSON.parse(localStorage.getItem('excluded_accounts_ids') || '[]')
  
  const allAccIds = new Set([...Object.keys(currentAccs), ...Object.keys(prevAccs)])
  
  allAccIds.forEach(id => {
    if (!excludedAccs.includes(id)) {
      const curBal = Number(currentAccs[id] || 0)
      const prevBal = hasRealPrevDetails ? Number(prevAccs[id] || 0) : curBal
      const diff = Math.round(curBal - prevBal)
      
      if (Math.abs(diff) > 0) {
        const acc = accounts.value.find(a => a.id === id)
        if (acc) {
          const currency = acc.currency || 'TWD'
          const rate = currency === 'USD' ? usdTwdRate.value : (currency === 'JPY' ? jpyTwdRate.value : 1)
          const diffTwd = Math.round(diff * rate)
          
          changes.push({
            name: acc.name,
            diff,
            diffTwd,
            currency,
            type: acc.type
          })
        }
      }
    }
  })
  
  const invDiff = prev ? current.invest - prev.invest : 0
  if (Math.round(invDiff) !== 0) {
    changes.push({
      name: '📈 投資市值波動',
      diff: Math.round(invDiff),
      diffTwd: Math.round(invDiff),
      currency: 'TWD',
      type: 'Invest'
    })
  }
  
  const liabDiff = prev ? current.liabilities - prev.liabilities : 0
  if (Math.round(liabDiff) !== 0) {
    changes.push({
      name: '🏦 負債總額變動',
      diff: -Math.round(liabDiff), // Negative means liability increased, causing net worth drop
      diffTwd: -Math.round(liabDiff),
      currency: 'TWD',
      type: 'Liability'
    })
  }

  const txs = []
  if (current.details?.transactions) {
    current.details.transactions.forEach(tx => {
      txs.push(tx)
    })
  }
  
  const liquidChanges = []
  const investChanges = []
  const liabChanges = []
  
  const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
  
  changes.forEach(chg => {
    if (chg.type === 'Invest') {
      investChanges.push(chg)
    } else if (chg.type === 'Liability' || liabTypes.includes(chg.type)) {
      liabChanges.push(chg)
    } else {
      liquidChanges.push(chg)
    }
  })
  
  return {
    date: current.date,
    netWorth: current.netWorth,
    diff: nwDiff,
    hasChanges: changes.length > 0,
    liquidChanges,
    investChanges,
    liabChanges,
    transactions: txs
  }
})

const trendDateRangeText = computed(() => {
  const history = filteredHistory.value
  if (history.length === 0) return ''
  const start = new Date(history[0].date)
  const end = new Date(history[history.length - 1].date)
  return `${start.getFullYear()}年${start.getMonth() + 1}月至${end.getMonth() + 1}月`
})

const netWorthSummaryText = computed(() => {
  const datasets = trendDatasets.value
  if (datasets.length < 2) return null
  
  const first = datasets[0]
  const last = datasets[datasets.length - 1]
  
  const formatDateStr = (dateStr) => {
    const d = new Date(dateStr)
    return `${d.getMonth() + 1}/${d.getDate()}`
  }
  
  const nwDiff = last.netWorth - first.netWorth
  const nwPct = first.netWorth !== 0 ? ((nwDiff / Math.abs(first.netWorth)) * 100).toFixed(2) : (nwDiff !== 0 ? '100.00' : '0.00')
  
  const liqDiff = last.liquid - first.liquid
  const invDiff = last.invest - first.invest
  const liabDiff = last.liabilities - first.liabilities
  
  return {
    startVal: first.netWorth,
    lastVal: last.netWorth,
    diff: nwDiff,
    pct: `${nwDiff >= 0 ? '+' : ''}${nwPct}%`,
    startDateStr: formatDateStr(first.date),
    liqDiff: Math.round(liqDiff),
    invDiff: Math.round(invDiff),
    liabDiff: Math.round(liabDiff)
  }
})
const liquidInvestSummaryText = computed(() => {
  const datasets = trendDatasets.value
  if (datasets.length < 2) return null
  
  const first = datasets[0]
  const last = datasets[datasets.length - 1]
  
  const formatDateStr = (dateStr) => {
    const d = new Date(dateStr)
    return `${d.getMonth() + 1}/${d.getDate()}`
  }
  
  const liqDiff = last.liquid - first.liquid
  const liqPct = first.liquid !== 0 ? ((liqDiff / Math.abs(first.liquid)) * 100).toFixed(2) : (liqDiff !== 0 ? '100.00' : '0.00')
  
  const invDiff = last.invest - first.invest
  const invPct = first.invest !== 0 ? ((invDiff / Math.abs(first.invest)) * 100).toFixed(2) : (invDiff !== 0 ? '100.00' : '0.00')
  
  return {
    startLiq: first.liquid,
    lastLiq: last.liquid,
    liqDiff: Math.round(liqDiff),
    liqPct: `${liqDiff >= 0 ? '+' : ''}${liqPct}%`,
    
    startInv: first.invest,
    lastInv: last.invest,
    invDiff: Math.round(invDiff),
    invPct: `${invDiff >= 0 ? '+' : ''}${invPct}%`,
    
    startDateStr: formatDateStr(first.date)
  }
})
const moneyFlowAnalysis = computed(() => {
  const datasets = trendDatasets.value
  if (datasets.length < 2) return null
  
  const last = datasets[datasets.length - 1]
  const firstRealRecord = datasets.find(d => d.details && d.details.accounts)
  
  // If there are no real records with account details, or only 1 day of real data exists, we cannot do a valid flow analysis
  if (!firstRealRecord || firstRealRecord.date === last.date) return null
  
  const first = firstRealRecord
  const liqDiff = Math.round(last.liquid - first.liquid)
  const invDiff = Math.round(last.invest - first.invest)
  
  const firstDetails = first.details || {}
  const lastDetails = last.details || {}
  const finalFirstAccounts = firstDetails.accounts || {}

  const accChanges = []
  if (finalFirstAccounts && lastDetails.accounts) {
    Object.entries(lastDetails.accounts).forEach(([id, lastBal]) => {
      const firstBal = finalFirstAccounts[id]
      if (firstBal !== undefined) {
        const diff = Math.round(Number(lastBal) - Number(firstBal))
        if (Math.abs(diff) > 0) {
          const acc = accounts.value.find(a => a.id === id)
          const name = acc ? acc.name : '未知帳戶'
          accChanges.push({ name, diff })
        }
      }
    })
  }

  // Collect all transactions in the period
  const periodTransactions = []
  datasets.forEach(d => {
    if (d.details && d.details.transactions) {
      d.details.transactions.forEach(tx => {
        periodTransactions.push(tx)
      })
    }
  })

  const sellTxList = periodTransactions.filter(tx => tx.type === 'sell')
  let profitSumTwd = 0
  let hasSellTrades = false
  if (sellTxList.length > 0) {
    hasSellTrades = true
    sellTxList.forEach(tx => {
      const p = Number(tx.profit || 0)
      const pTwd = Math.round(tx.currency === 'USD' ? p * usdTwdRate.value : p)
      profitSumTwd += pTwd
    })
  }

  let tradeProfitText = ''
  if (hasSellTrades) {
    tradeProfitText = `（本期累計實現損益：${profitSumTwd >= 0 ? '獲利' : '虧損'} ${formatInvestNumber(Math.abs(profitSumTwd))} 元）`
  }

  const periodLots = investments.value.filter(inv => {
    if (!inv.buy_date) return false
    return inv.buy_date >= first.date && inv.buy_date <= last.date
  })
  
  const flowItems = []
  
  // 1) Outflows (Buys)
  if (periodLots.length > 0) {
    const flows = {}
    periodLots.forEach(lot => {
      const fundId = lot.funding_account_id
      if (fundId) {
        const acc = accounts.value.find(a => a.id === fundId)
        const accName = acc ? acc.name : '未知帳戶'
        if (!flows[accName]) flows[accName] = {}
        const sym = lot.symbol.toUpperCase()
        const lotCost = Number(lot.quantity || 0) * Number(lot.buy_price || lot.average_cost || 0)
        const lotCostTwd = Math.round(lot.currency === 'USD' ? lotCost * usdTwdRate.value : lotCost)
        flows[accName][sym] = (flows[accName][sym] || 0) + lotCostTwd
      }
    })
    
    Object.entries(flows).forEach(([accName, stocks]) => {
      const detailStr = Object.entries(stocks).map(([sym, cost]) => `${sym} (${formatInvestNumber(cost)} 元)`).join('、')
      flowItems.push({
        type: 'buy',
        accountName: accName,
        stockDetails: detailStr,
        text: `從 [${accName}] 流入股市：${detailStr}`
      })
    })
  }
  
  // 2) Inflows (Sells)
  if (sellTxList.length > 0) {
    const inflowFlows = {}
    sellTxList.forEach(tx => {
      const fundId = tx.funding_account_id
      if (fundId) {
        const acc = accounts.value.find(a => a.id === fundId)
        const accName = acc ? acc.name : '未知帳戶'
        if (!inflowFlows[accName]) inflowFlows[accName] = {}
        const sym = tx.symbol.toUpperCase()
        const valTwd = Math.round(Number(tx.quantity || 0) * Number(tx.price || 0) * (tx.currency === 'USD' ? usdTwdRate.value : 1))
        inflowFlows[accName][sym] = (inflowFlows[accName][sym] || 0) + valTwd
      }
    })
    
    Object.entries(inflowFlows).forEach(([accName, stocks]) => {
      const detailStr = Object.entries(stocks).map(([sym, val]) => `${sym} (${formatInvestNumber(val)} 元)`).join('、')
      flowItems.push({
        type: 'sell',
        accountName: accName,
        stockDetails: detailStr,
        text: `賣出變現匯入 [${accName}]：${detailStr}`
      })
    })
  }
  
  let totalBuyAmtTwd = 0
  if (periodLots.length > 0) {
    periodLots.forEach(lot => {
      const lotCost = Number(lot.quantity || 0) * Number(lot.buy_price || lot.average_cost || 0)
      const lotCostTwd = Math.round(lot.currency === 'USD' ? lotCost * usdTwdRate.value : lotCost)
      totalBuyAmtTwd += lotCostTwd
    })
  }

  let totalSellAmtTwd = 0
  if (sellTxList.length > 0) {
    sellTxList.forEach(tx => {
      const valTwd = Math.round(Number(tx.quantity || 0) * Number(tx.price || 0) * (tx.currency === 'USD' ? usdTwdRate.value : 1))
      totalSellAmtTwd += valTwd
    })
  }
  
  const netFlow = totalSellAmtTwd - totalBuyAmtTwd

  // Case 1: Net flow to stock market (bought more than sold)
  if (netFlow < 0) {
    const summary = totalSellAmtTwd > 0
      ? `本期賣出股市部位 ${formatInvestNumber(totalSellAmtTwd)} 元，買入投入股市 ${formatInvestNumber(totalBuyAmtTwd)} 元。`
      : `本期買入投入股市 ${formatInvestNumber(totalBuyAmtTwd)} 元。`
    return {
      type: 'reallocation',
      title: '資金配置轉移',
      icon: '🔄',
      summary,
      tradeProfitText,
      accountsFlow: accChanges,
      investFlow: flowItems
    }
  }
  
  // Case 3: Net flow from stock market (sold more than bought)
  if (netFlow > 0) {
    const summary = totalBuyAmtTwd > 0
      ? `本期賣出股市部位 ${formatInvestNumber(totalSellAmtTwd)} 元，買入投入股市 ${formatInvestNumber(totalBuyAmtTwd)} 元。`
      : `本期賣出股市部位 ${formatInvestNumber(totalSellAmtTwd)} 元。`
    return {
      type: 'cashout',
      title: '投資部位變現',
      icon: '🏦',
      summary,
      tradeProfitText,
      accountsFlow: accChanges,
      investFlow: flowItems
    }
  }
  
  // Case 2 & 4: No net stock transaction flow (netFlow === 0)
  if (liqDiff < 0) {
    return {
      type: 'outflow',
      title: '日常支出與市值波動',
      icon: '💸',
      summary: `本期流動資金減少 ${formatInvestNumber(Math.abs(liqDiff))} 元，投資部位變動 ${formatInvestNumber(Math.abs(invDiff))} 元。`,
      tradeProfitText,
      accountsFlow: accChanges,
      investFlow: flowItems
    }
  } else {
    return {
      type: 'growth',
      title: '資產流動紀錄',
      icon: '📈',
      summary: `本期流動資金增加 ${formatInvestNumber(liqDiff)} 元，投資部位變動 ${formatInvestNumber(invDiff)} 元。`,
      tradeProfitText,
      accountsFlow: accChanges,
      investFlow: flowItems
    }
  }
})


const trendPeriodROI = computed(() => {
  const datasets = trendDatasets.value
  if (datasets.length < 2) return 0
  const first = datasets[0]
  const last = datasets[datasets.length - 1]
  
  if (trendType.value === 'net_worth') {
    const base = Math.abs(first.netWorth)
    if (base === 0) return 0
    return ((last.netWorth - first.netWorth) / base) * 100
  } else {
    const base = Math.abs(first.invest)
    if (base === 0) return 0
    return ((last.invest - first.invest) / base) * 100
  }
})

const getGroupColor = (grp) => {
  const colors = ['#7839ec', '#5c67f5', '#2ec173', '#a0a0a5', '#ff9f0a', '#64d2ff', '#bf5af2', '#ff453a']
  const activeGroups = Array.from(new Set(investments.value.filter(i => Number(i.quantity || 0) > 0 && i.include_in_chart !== false).map(i => i.custom_group || '未分類'))).sort()
  const idx = activeGroups.indexOf(grp)
  return idx !== -1 ? colors[idx % colors.length] : '#7839ec'
}

const trendRoiSummaryText = computed(() => {
  const groupMetrics = {}
  
  investments.value.forEach(item => {
    const qty = Number(item.quantity || 0)
    if (qty <= 0 || item.include_in_chart === false) return
    const cost = Number(item.buy_price || item.average_cost || 0)
    const current = Number(item.current_price || 0)
    const currency = item.currency || 'TWD'
    const grp = item.custom_group || '未分類'
    
    const isUS = currency === 'USD' || (item.asset_class || '').toLowerCase() === 'us_stock'
    const costTwd = isUS ? qty * cost * usdTwdRate.value : qty * cost
    const valTwd = isUS ? qty * current * usdTwdRate.value : qty * current

    if (!groupMetrics[grp]) {
      groupMetrics[grp] = { cost: 0, val: 0 }
    }
    groupMetrics[grp].cost += costTwd
    groupMetrics[grp].val += valTwd
  })

  const summaries = {}
  for (const [grp, metrics] of Object.entries(groupMetrics)) {
    if (metrics.cost > 0) {
      const roi = ((metrics.val - metrics.cost) / metrics.cost) * 100
      summaries[grp] = `${grp}：${roi >= 0 ? '+' : ''}${roi.toFixed(2)}%`
    }
  }
  return summaries
})

// 各群組真實投資報酬率（給今日快覽卡片用）
const roiByGroup = computed(() => {
  const groupMetrics = {}

  investments.value.forEach(item => {
    const qty = Number(item.quantity || 0)
    if (qty <= 0 || item.include_in_chart === false) return
    const cost = Number(item.buy_price || item.average_cost || 0)
    const current = Number(item.current_price || 0)
    const currency = item.currency || 'TWD'
    const grp = item.custom_group || '未分類'

    const isUS = currency === 'USD' || (item.asset_class || '').toLowerCase() === 'us_stock'
    const costTwd = isUS ? qty * cost * usdTwdRate.value : qty * cost
    const valTwd = isUS ? qty * current * usdTwdRate.value : qty * current

    if (!groupMetrics[grp]) {
      groupMetrics[grp] = { cost: 0, val: 0 }
    }
    groupMetrics[grp].cost += costTwd
    groupMetrics[grp].val += valTwd
  })

  const result = {}
  for (const [grp, m] of Object.entries(groupMetrics)) {
    const pnl = m.val - m.cost
    const roi = m.cost > 0 ? (pnl / m.cost) * 100 : 0
    result[grp] = { cost: m.cost, val: m.val, pnl, roi }
  }
  return result
})

// ── ROI 歷史走勢圖 ──────────────────────────────────────────────────
const investmentPriceHistory = ref({}) // { yhSymbol: { dates: string[], closes: number[], isUS: bool, qty: number, ... } }
const isFetchingRoiHistory = ref(false)
const roiHistoryError = ref('')

const getRoiHistoryRange = (filter) => {
  switch (filter) {
    case '30D': return '1mo'
    case '6M':  return '6mo'
    case '1Y':  return '1y'
    case 'YTD': return 'ytd'
    case 'ALL': return '2y'
    default:    return '6mo'
  }
}

const fetchHistoricalPricesForSymbol = async (yhSymbol, range) => {
  const isProd = import.meta.env.PROD
  const yhUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${yhSymbol}?interval=1d&range=${range}`

  const tryFetch = async (url) => {
    try {
      const res = await fetch(url)
      if (!res.ok) return null
      const data = await res.json()
      const result = data?.chart?.result?.[0]
      if (!result) return null
      const timestamps = result.timestamp || []
      const closes = result.indicators?.quote?.[0]?.close || []
      if (timestamps.length === 0) return null
      const dates = []
      const validCloses = []
      for (let i = 0; i < timestamps.length; i++) {
        if (closes[i] != null) {
          const d = new Date(timestamps[i] * 1000)
          dates.push(d.toISOString().split('T')[0])
          validCloses.push(closes[i])
        }
      }
      return { dates, closes: validCloses }
    } catch { return null }
  }

  if (!isProd) {
    const r = await tryFetch(`/yahoo-finance/v8/finance/chart/${yhSymbol}?interval=1d&range=${range}`)

    if (r) return r
  }

  const proxies = [
    `/api/yahoo-proxy?symbol=${yhSymbol}&range=${range}`,
    `https://corsproxy.io/?${encodeURIComponent(yhUrl)}`,
    `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(yhUrl)}`,
    `https://api.allorigins.win/raw?url=${encodeURIComponent(yhUrl)}`
  ]
  for (const proxyUrl of proxies) {
    const r = await tryFetch(proxyUrl)
    if (r) return r
  }
  return null
}

const fetchAllRoiHistory = async () => {
  if (isFetchingRoiHistory.value) return
  isFetchingRoiHistory.value = true
  roiHistoryError.value = ''

  const range = getRoiHistoryRange(timeFilter.value)
  const cacheKey = `roi_price_history_v1_${range}`

  // Try localStorage cache (TTL: 4 hours)
  try {
    const cached = localStorage.getItem(cacheKey)
    if (cached) {
      const { data, timestamp } = JSON.parse(cached)
      if (Date.now() - timestamp < 4 * 3600 * 1000) {
        investmentPriceHistory.value = data
        isFetchingRoiHistory.value = false
        return
      }
    }
  } catch {}

  // Build symbol map
  const symbolMap = {}
  investments.value.forEach(inv => {
    if (Number(inv.quantity || 0) <= 0 || inv.include_in_chart === false) return
    const sym = inv.symbol.toUpperCase()
    const yhSym = getYahooSymbol(sym, inv.asset_class)
    if (!symbolMap[yhSym]) symbolMap[yhSym] = { original: sym, assetClass: inv.asset_class }
  })

  const result = {}
  for (const [yhSym] of Object.entries(symbolMap)) {
    const data = await fetchHistoricalPricesForSymbol(yhSym, range)
    if (data) result[yhSym] = data
  }

  investmentPriceHistory.value = result
  try {
    localStorage.setItem(cacheKey, JSON.stringify({ data: result, timestamp: Date.now() }))
  } catch {}

  if (Object.keys(result).length === 0) roiHistoryError.value = '暫時無法取得歷史價格資料，請稍後再試'
  isFetchingRoiHistory.value = false
}

// ── 歷史 ROI 折線圖資料 ─────────────────────────────────────
const roiHistoryChartData = computed(() => {
  const history = investmentPriceHistory.value
  if (Object.keys(history).length === 0) return null

  // Build price lookup: yhSymbol -> { date -> close }
  const priceLookup = {}
  Object.entries(history).forEach(([yhSym, h]) => {
    priceLookup[yhSym] = {}
    h.dates.forEach((d, i) => { priceLookup[yhSym][d] = h.closes[i] })
  })

  // Collect date union from all available symbols
  const dateSet = new Set()
  Object.values(history).forEach(h => h.dates.forEach(d => dateSet.add(d)))
  let dates = Array.from(dateSet).sort()

  // Apply custom date range filter
  if (timeFilter.value === 'ALL') {
    dates = dates.filter(d => d >= customStartDate.value && d <= customEndDate.value)
  }
  if (dates.length < 2) return null

  // LOCF helpers — build sorted date arrays per symbol
  const sortedDatesPerSym = {}
  Object.entries(priceLookup).forEach(([yhSym, priceMap]) => {
    sortedDatesPerSym[yhSym] = Object.keys(priceMap).sort()
  })

  // Get last known price on or before a given date (Last Observation Carried Forward)
  const getLastKnownPrice = (yhSym, date) => {
    const priceMap = priceLookup[yhSym]
    if (!priceMap) return null
    if (priceMap[date] != null) return priceMap[date]
    const symDates = sortedDatesPerSym[yhSym]
    let lo = 0, hi = symDates.length - 1, found = null
    while (lo <= hi) {
      const mid = (lo + hi) >> 1
      if (symDates[mid] <= date) { found = symDates[mid]; lo = mid + 1 }
      else hi = mid - 1
    }
    return found ? priceMap[found] : null
  }

  // Build investment list with buy_date
  const invList = investments.value
    .filter(inv => Number(inv.quantity || 0) > 0 && inv.include_in_chart !== false)
    .map(inv => {
      const sym = inv.symbol.toUpperCase()
      const yhSym = getYahooSymbol(sym, inv.asset_class)
      const isUS = (inv.currency || 'TWD') === 'USD' || (inv.asset_class || '').toLowerCase() === 'us_stock'
      const qty = Number(inv.quantity || 0)
      const buyPrice = Number(inv.buy_price || inv.average_cost || 0)
      const costTwd = isUS ? qty * buyPrice * usdTwdRate.value : qty * buyPrice
      // buy_date prevents ROI from including pre-purchase historical prices
      const buyDate = inv.buy_date ? inv.buy_date.slice(0, 10) : '1970-01-01'
      return { yhSym, isUS, qty, costTwd, grp: inv.custom_group || '未分類', buyDate }
    })

  const allGroupNames = [...new Set(invList.map(inv => inv.grp))]
  const GROUP_COLORS = ['#7839ec', '#5c67f5', '#2ec173', '#ff9f0a', '#64d2ff', '#bf5af2', '#ff453a', '#a0a0a5']

  if (invList.reduce((s, inv) => s + inv.costTwd, 0) <= 0) return null

  // ROI calculation per date
  // Key fix: each investment only contributes (both value AND cost) from its buy_date onwards.
  // This eliminates artificial dips from comparing today's cost basis against pre-purchase prices.
  const overallRoi = []
  const groupRoi = {}
  allGroupNames.forEach(g => { groupRoi[g] = [] })

  dates.forEach(date => {
    let totalVal = 0
    let activeCost = 0
    const groupVal = {}
    const groupActiveCost = {}

    invList.forEach(inv => {
      if (date < inv.buyDate) return  // Not purchased yet — exclude from both val and cost

      const price = getLastKnownPrice(inv.yhSym, date)
      if (price == null) return  // No price data at all for this symbol

      const valTwd = inv.isUS ? inv.qty * price * usdTwdRate.value : inv.qty * price
      totalVal += valTwd
      activeCost += inv.costTwd
      groupVal[inv.grp] = (groupVal[inv.grp] || 0) + valTwd
      groupActiveCost[inv.grp] = (groupActiveCost[inv.grp] || 0) + inv.costTwd
    })

    overallRoi.push(activeCost > 0 ? ((totalVal - activeCost) / activeCost) * 100 : null)
    allGroupNames.forEach(g => {
      const gCost = groupActiveCost[g] || 0
      const gVal = groupVal[g] || 0
      groupRoi[g].push(gCost > 0 ? ((gVal - gCost) / gCost) * 100 : null)
    })
  })

  // Trim leading nulls — don't show empty period before any investment existed
  const firstActiveIdx = overallRoi.findIndex(v => v !== null)
  if (firstActiveIdx < 0) return null
  const trimmedDates = dates.slice(firstActiveIdx)
  const trimmedOverall = overallRoi.slice(firstActiveIdx)
  const trimmedGroup = {}
  allGroupNames.forEach(g => { trimmedGroup[g] = groupRoi[g].slice(firstActiveIdx) })

  const labels = trimmedDates.map(d => {
    const dt = new Date(d + 'T00:00:00')
    return `${dt.getMonth() + 1}/${dt.getDate()}`
  })

  const datasets = []
  datasets.push({
    label: '整體',
    data: trimmedOverall,
    borderColor: '#5c67f5',
    backgroundColor: 'rgba(0,0,0,0)',
    borderWidth: 2.5,
    tension: 0.3,
    fill: false,
    spanGaps: true,
    pointRadius: trimmedDates.length > 40 ? 0 : 2,
    pointHoverRadius: 5,
    order: 0
  })
  allGroupNames.forEach((grp, idx) => {
    datasets.push({
      label: grp,
      data: trimmedGroup[grp],
      borderColor: getGroupColor(grp),
      backgroundColor: 'rgba(0,0,0,0)',
      borderWidth: 2,
      tension: 0.3,
      fill: false,
      spanGaps: true,
      pointRadius: trimmedDates.length > 40 ? 0 : 2,
      pointHoverRadius: 5,
      order: idx + 1
    })
  })

  return { labels, datasets }
})

const roiHistoryChartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  elements: {
    line: {
      fill: false  // Globally disable Filler plugin for all lines in this chart
    }
  },
  plugins: {
    legend: {
      display: true,
      position: 'top',
      labels: {
        color: 'var(--color-text)',
        font: { size: 10, family: 'Inter', weight: 'bold' },
        boxWidth: 8, boxHeight: 8, padding: 10,
        usePointStyle: true,
        pointStyle: 'line'
      }
    },
    tooltip: {
      backgroundColor: 'rgba(20,20,25,0.97)',
      titleColor: '#ffffff',
      bodyColor: '#c0c0cc',
      borderColor: 'rgba(255,255,255,0.08)',
      borderWidth: 1,
      padding: 10,
      cornerRadius: 10,
      callbacks: {
        label: (ctx) => {
          const v = ctx.parsed.y
          return ` ${ctx.dataset.label}: ${v >= 0 ? '+' : ''}${v.toFixed(2)}%`
        }
      }
    }
  },
  scales: {
    y: {
      grid: { color: 'rgba(120,120,140,0.12)' },
      ticks: {
        color: 'var(--color-text-muted)',
        font: { size: 10, family: 'Inter' },
        callback: (v) => (v >= 0 ? '+' : '') + v.toFixed(1) + '%'
      }
    },
    x: {
      grid: { display: false },
      ticks: {
        color: 'var(--color-text-muted)',
        font: { size: 10, family: 'Inter' },
        maxTicksLimit: 8
      }
    }
  }
}))

// 切換時間篩選器 → 清快取並重新抓取
watch(timeFilter, () => {
  investmentPriceHistory.value = {}
  if (currentTab.value === 'trend') fetchAllRoiHistory()
})

// 切換到趨勢圖 tab → 確保歷史資料已載入
watch(currentTab, (tab) => {
  if (tab === 'trend' && Object.keys(investmentPriceHistory.value).length === 0) {
    fetchAllRoiHistory()
  }
})

// 切換到 ROI tab → 確保歷史資料已載入
watch(trendType, (type) => {
  if (type === 'roi' && Object.keys(investmentPriceHistory.value).length === 0) {
    fetchAllRoiHistory()
  }
})

const netWorthChartData = computed(() => {
  const datasets = trendDatasets.value
  const labels = datasets.map(r => {
    const d = new Date(r.date)
    return `${d.getMonth() + 1}月`
  })
  const nwData = datasets.map(r => r.netWorth)
  const liabData = datasets.map(r => r.liabilities)
  return {
    labels,
    datasets: [
      {
        label: '我的淨資產',
        data: nwData,
        borderColor: '#5c67f5',
        tension: 0.35,
        borderWidth: 2.5,
        fill: false,
        pointRadius: datasets.length > 20 ? 0 : 2,
        pointHoverRadius: 5
      },
      {
        label: '負債',
        data: liabData,
        borderColor: '#a0a0a5',
        borderDash: [5, 5],
        tension: 0.35,
        borderWidth: 2.5,
        fill: false,
        pointRadius: datasets.length > 20 ? 0 : 2,
        pointHoverRadius: 5
      }
    ]
  }
})

const liquidInvestChartData = computed(() => {
  const datasets = trendDatasets.value
  const labels = datasets.map(r => {
    const d = new Date(r.date)
    return `${d.getMonth() + 1}月`
  })
  const liquidData = datasets.map(r => r.liquid)
  const investData = datasets.map(r => r.invest)
  return {
    labels,
    datasets: [
      {
        label: '流動資金',
        data: liquidData,
        borderColor: '#2ec173',
        tension: 0.35,
        borderWidth: 2.5,
        fill: false,
        pointRadius: datasets.length > 20 ? 0 : 2,
        pointHoverRadius: 5
      },
      {
        label: '投資',
        data: investData,
        borderColor: '#7839ec',
        tension: 0.35,
        borderWidth: 2.5,
        fill: false,
        pointRadius: datasets.length > 20 ? 0 : 2,
        pointHoverRadius: 5
      }
    ]
  }
})

const netWorthChartOptions = computed(() => {
  return {
    responsive: true,
    maintainAspectRatio: false,
    onClick: (event, elements) => {
      if (elements && elements.length > 0) {
        const index = elements[0].index
        selectedHistoryIndex.value = index
      }
    },
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: 'rgba(30, 30, 32, 0.95)',
        titleColor: '#ffffff',
        bodyColor: '#e0e0e5',
        borderColor: 'rgba(255, 255, 255, 0.08)',
        borderWidth: 1,
        padding: 10,
        cornerRadius: 8,
        callbacks: {
          label: (context) => {
            let label = context.dataset.label || ''
            if (label) label += ': '
            const valStr = isHidden.value ? '•••••• 元' : context.parsed.y.toLocaleString('zh-TW', { minimumFractionDigits: 0, maximumFractionDigits: 0 }) + ' 元'
            label += valStr
            
            const datasets = trendDatasets.value
            if (datasets.length >= 2) {
              const firstVal = context.datasetIndex === 0 ? datasets[0].netWorth : datasets[0].liabilities
              if (firstVal && firstVal !== 0) {
                const diff = context.parsed.y - firstVal
                const pct = (diff / Math.abs(firstVal)) * 100
                label += ` (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`
              } else if (firstVal === 0 && context.parsed.y !== 0) {
                label += ' (+100.00%)'
              }
            }
            return label
          }
        }
      }
    },
    scales: {
      y: {
        grid: { color: 'rgba(255, 255, 255, 0.05)' },
        ticks: { 
          color: 'rgba(255, 255, 255, 0.4)', 
          font: { size: 10, family: 'Inter' },
          callback: (value) => {
            if (isHidden.value) return '***'
            if (Math.abs(value) >= 1000000) return (value / 1000000) + 'm'
            if (Math.abs(value) >= 1000) return (value / 1000) + 'k'
            return value
          }
        }
      },
      x: {
        grid: { display: false },
        ticks: { color: 'rgba(255, 255, 255, 0.4)', font: { size: 10, family: 'Inter' }, maxTicksLimit: 8 }
      }
    }
  }
})

const liquidInvestChartOptions = computed(() => {
  return {
    responsive: true,
    maintainAspectRatio: false,
    onClick: (event, elements) => {
      if (elements && elements.length > 0) {
        const index = elements[0].index
        selectedHistoryIndex.value = index
      }
    },
    interaction: { mode: 'index', intersect: false },
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: 'rgba(30, 30, 32, 0.95)',
        titleColor: '#ffffff',
        bodyColor: '#e0e0e5',
        borderColor: 'rgba(255, 255, 255, 0.08)',
        borderWidth: 1,
        padding: 10,
        cornerRadius: 8,
        callbacks: {
          label: (context) => {
            let label = context.dataset.label || ''
            if (label) label += ': '
            const valStr = isHidden.value ? '•••••• 元' : context.parsed.y.toLocaleString('zh-TW', { minimumFractionDigits: 0, maximumFractionDigits: 0 }) + ' 元'
            label += valStr
            
            const datasets = trendDatasets.value
            if (datasets.length >= 2) {
              const firstVal = context.datasetIndex === 0 ? datasets[0].liquid : datasets[0].invest
              if (firstVal && firstVal !== 0) {
                const diff = context.parsed.y - firstVal
                const pct = (diff / Math.abs(firstVal)) * 100
                label += ` (${pct >= 0 ? '+' : ''}${pct.toFixed(2)}%)`
              } else if (firstVal === 0 && context.parsed.y !== 0) {
                label += ' (+100.00%)'
              }
            }
            return label
          }
        }
      }
    },
    scales: {
      y: {
        grid: { color: 'rgba(255, 255, 255, 0.05)' },
        ticks: { 
          color: 'rgba(255, 255, 255, 0.4)', 
          font: { size: 10, family: 'Inter' },
          callback: (value) => {
            if (isHidden.value) return '***'
            if (Math.abs(value) >= 1000000) return (value / 1000000) + 'm'
            if (Math.abs(value) >= 1000) return (value / 1000) + 'k'
            return value
          }
        }
      },
      x: {
        grid: { display: false },
        ticks: { color: 'rgba(255, 255, 255, 0.4)', font: { size: 10, family: 'Inter' }, maxTicksLimit: 8 }
      }
    }
  }
})

// 圓餅圖分配資料
const doughnutChartData = computed(() => {
  const assets = totalLiquidAssets.value
  const inv = totalInvestments.value
  const fixed = totalFixedAssets.value
  const recv = totalReceivables.value
  const liab = totalLiabilities.value

  const hasData = assets > 0 || inv > 0 || fixed > 0 || recv > 0 || liab > 0
  if (!hasData) {
    return {
      labels: ['無資料'],
      datasets: [{ backgroundColor: ['#eaeaff'], data: [1], borderWidth: 0 }]
    }
  }

  const labels = []
  const data = []
  const colors = []

  if (assets > 0) { labels.push('流動資金'); data.push(assets); colors.push('#5ebd74') }
  if (inv > 0)    { labels.push('投資'); data.push(inv);    colors.push('#5c67f5') }
  if (fixed > 0)   { labels.push('固定資產'); data.push(fixed);   colors.push('#3a59cc') }
  if (recv > 0)   { labels.push('應收款'); data.push(recv);   colors.push('#8ba4e8') }
  if (liab > 0)   { labels.push('負債'); data.push(liab);   colors.push('#ccd7f5') }

  return {
    labels,
    datasets: [{
      backgroundColor: colors,
      data,
      borderWidth: 2,
      borderColor: '#f3f5f8',
      hoverOffset: 4
    }]
  }
})

const doughnutChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '84%',
  plugins: {
    legend: { display: false }
  }
}

// ── Functions ─────────────────────────────────────────────────────
const togglePrivacy = () => { isHidden.value = !isHidden.value }

const mergeExclusionSettings = () => {
  const excludedAccs = JSON.parse(localStorage.getItem('excluded_accounts_ids') || '[]')
  accounts.value.forEach(a => {
    a.include_in_chart = !excludedAccs.includes(a.id)
  })

  const excludedInvs = JSON.parse(localStorage.getItem('excluded_investments_ids') || '[]')
  investments.value.forEach(i => {
    i.include_in_chart = !excludedInvs.includes(i.id)
  })
}

const fetchAllData = async () => {
  if (isSyncingData.value) return
  isSyncingData.value = true
  // 1. 快取優先渲染 (SWR) — 如果本機有舊資料，直接先呈現在畫面上，達成秒開效果
  const cachedAccs = localStorage.getItem('local_accounts')
  const cachedInvs = localStorage.getItem('local_investments')
  const cachedRate = localStorage.getItem('cached_usd_twd_rate')
  const cachedJpyRate = localStorage.getItem('cached_jpy_twd_rate')
  
  if (cachedAccs || cachedInvs) {
    if (cachedAccs) accounts.value = JSON.parse(cachedAccs)
    if (cachedInvs) investments.value = JSON.parse(cachedInvs)
    if (cachedRate) usdTwdRate.value = Number(cachedRate)
    if (cachedJpyRate) jpyTwdRate.value = Number(cachedJpyRate)
    mergeExclusionSettings()
    isInitialDataLoaded.value = true
  }

  // 2. 背景抓取即時匯率
  try {
    const res = await fetch('https://api.exchangerate-api.com/v4/latest/USD')
    const rateData = await res.json()
    usdTwdRate.value = rateData.rates?.TWD ?? 32
    const usdJpy = rateData.rates?.JPY ?? 158
    jpyTwdRate.value = usdTwdRate.value / usdJpy
    localStorage.setItem('cached_usd_twd_rate', usdTwdRate.value.toString())
    localStorage.setItem('cached_jpy_twd_rate', jpyTwdRate.value.toString())
  } catch {
    if (!cachedRate) usdTwdRate.value = 32
    if (!cachedJpyRate) jpyTwdRate.value = 0.21
  }

  // 清除快取中舊有的 Mock 資料
  let localAccs = JSON.parse(localStorage.getItem('local_accounts') || '[]')
  if (localAccs.some(a => String(a.id).startsWith('mock-'))) {
    localAccs = localAccs.filter(a => !String(a.id).startsWith('mock-'))
    localStorage.setItem('local_accounts', JSON.stringify(localAccs))
  }

  let localInvs = JSON.parse(localStorage.getItem('local_investments') || '[]')
  if (localInvs.some(i => String(i.id).startsWith('mock-'))) {
    localInvs = localInvs.filter(i => !String(i.id).startsWith('mock-'))
    localStorage.setItem('local_investments', JSON.stringify(localInvs))
  }

  // 3. 背景獲取最新帳戶資料 (Supabase)
  let loadedAccounts = []
  try {
    const { data: accs, error: accsErr } = await supabase
      .from('accounts')
      .select('*')
      .order('created_at', { ascending: true })
    
    if (!accsErr && accs) {
      loadedAccounts = accs
      localStorage.setItem('local_accounts', JSON.stringify(accs))
    } else {
      loadedAccounts = JSON.parse(localStorage.getItem('local_accounts') || '[]')
    }
  } catch (err) {
    console.warn('Supabase accounts query failed, loading locally:', err)
    loadedAccounts = JSON.parse(localStorage.getItem('local_accounts') || '[]')
  }
  
  // Sanitizer: Ensure no account balance has decimals (self-healing for legacy/float data)
  let accountsChangedLocally = false
  loadedAccounts.forEach(acc => {
    const rounded = Math.round(Number(acc.balance || 0))
    if (acc.balance !== rounded) {
      acc.balance = rounded
      accountsChangedLocally = true
      // Push update async to database
      supabase.from('accounts').update({ balance: rounded }).eq('id', acc.id)
        .then(({ error }) => {
          if (error) console.warn(`Failed to sanitize balance for account ${acc.name}:`, error)
        })
    }
  })
  if (accountsChangedLocally) {
    localStorage.setItem('local_accounts', JSON.stringify(loadedAccounts))
  }
  accounts.value = loadedAccounts

  // 4. 背景獲取最新投資資料 (Supabase)
  let loadedInvestments = []
  try {
    const { data: invs, error: invsErr } = await supabase
      .from('investments')
      .select('*')
      .order('created_at', { ascending: false })
      
    if (!invsErr && invs) {
      // Safety net: if Supabase returned empty custom_group but local has one, keep local
      // Guards against race conditions where page refresh outpaces Supabase write
      const localInvMap = {}
      JSON.parse(localStorage.getItem('local_investments') || '[]').forEach(i => {
        if (i.custom_group) localInvMap[i.id] = i.custom_group
      })
      loadedInvestments = invs.map(i => ({
        ...i,
        custom_group: i.custom_group || localInvMap[i.id] || ''
      }))
      localStorage.setItem('local_investments', JSON.stringify(loadedInvestments))
    } else {
      loadedInvestments = JSON.parse(localStorage.getItem('local_investments') || '[]')
    }
  } catch (err) {
    console.warn('Supabase investments query failed, loading locally:', err)
    loadedInvestments = JSON.parse(localStorage.getItem('local_investments') || '[]')
  }
  
  investments.value = loadedInvestments
  
  // 套用本機的圖表排除設定 (因為 Supabase DB 無 include_in_chart 欄位)
  mergeExclusionSettings()

  // 所有最新資料同步完成後，確保關閉載入畫面
  isInitialDataLoaded.value = true

  // 5. 處理自動記帳 / 自動轉帳
  await processAutoRecords()

  // 6. 儲存每日資產快照
  await saveDailySnapshot(netWorth.value)

  // 6. Sync groups list
  syncGroups()
  isSyncingData.value = false
}

const handleSyncAll = async () => {
  if (isSyncingData.value || isRefreshing.value) return
  await fetchAllData()
  await refreshPrices()
}

const saveDailySnapshot = async (amount) => {
  const d = new Date()
  const offset = d.getTimezoneOffset()
  const localDate = new Date(d.getTime() - (offset * 60 * 1000))
  const dateStr = localDate.toISOString().split('T')[0]
  
  const details = {
    accounts: accounts.value.reduce((acc, curr) => {
      acc[curr.id] = Number(curr.balance)
      return acc
    }, {}),
    investments_value: totalInvestments.value,
    investments_cost: totalInvestmentCostTwd.value,
    transactions: todayTransactions.value
  }
  
  try {
    const { error } = await supabase
      .from('net_worth_history')
      .upsert({ date: dateStr, amount, details }, { onConflict: 'date' })
    if (error) saveSnapshotToLocal(dateStr, amount, details)
  } catch {
    saveSnapshotToLocal(dateStr, amount, details)
  }
  
  await fetchHistoricalSnapshots()
}

const saveSnapshotToLocal = (dateStr, amount, details) => {
  let history = JSON.parse(localStorage.getItem('net_worth_history') || '[]')
  const index = history.findIndex(h => h.date === dateStr)
  if (index !== -1) {
    history[index].amount = amount
    history[index].details = details
  } else {
    history.push({ date: dateStr, amount, details })
  }
  history.sort((a, b) => new Date(a.date) - new Date(b.date))
  localStorage.setItem('net_worth_history', JSON.stringify(history))
}

const fetchHistoricalSnapshots = async () => {
  let dbRecords = []
  try {
    const { data, error } = await supabase
      .from('net_worth_history')
      .select('date, amount, details')
      .order('date', { ascending: true })
    if (!error && data) dbRecords = data
  } catch {}

  const localRecords = JSON.parse(localStorage.getItem('net_worth_history') || '[]')
  const merged = {}
  localRecords.forEach(r => merged[r.date] = { amount: Number(r.amount), details: r.details || null })
  dbRecords.forEach(r => merged[r.date] = { amount: Number(r.amount), details: r.details || null })

  historyRecords.value = Object.entries(merged).map(([date, item]) => ({
    date,
    amount: item.amount,
    details: item.details
  })).sort((a, b) => new Date(a.date) - new Date(b.date))

  // 生成模擬成長曲線（改為平緩的當前淨資產，避免未有歷史紀錄時出現虛假的增長幅度）
  if (historyRecords.value.length <= 1) {
    const today = new Date()
    const mockData = []
    for (let i = 5; i >= 0; i--) {
      const d = new Date(today.getFullYear(), today.getMonth() - i, today.getDate())
      const dateStr = d.toISOString().split('T')[0]
      mockData.push({
        date: dateStr,
        amount: netWorth.value
      })
    }
    historyRecords.value = mockData
  }

  const todayStr = new Date().toISOString().split('T')[0]
  const todayRecord = historyRecords.value.find(h => h.date === todayStr)
  if (todayRecord && todayRecord.details && todayRecord.details.transactions) {
    todayTransactions.value = todayRecord.details.transactions
  } else {
    todayTransactions.value = []
  }
}

// Yahoo Finance symbol resolver
const getYahooSymbol = (symbol, assetClass) => {
  if (!symbol) return ''
  const sym = symbol.trim().toUpperCase()
  const cls = (assetClass || '').trim().toLowerCase()
  
  // If it already has a suffix like .TW, .TWO, -USD, =X, return as is
  if (sym.endsWith('.TW') || sym.endsWith('.TWO') || sym.includes('-') || sym.includes('=')) {
    return sym
  }
  
  // Taiwan stock: 4-6 digit numeric code or tw_stock class
  if (cls === 'tw_stock' || /^\d{4,6}$/.test(sym)) {
    return `${sym}.TW`
  }
  
  // Crypto: BTC, ETH, etc. -> BTC-USD
  if (cls === 'crypto' || ['BTC', 'ETH', 'SOL', 'USDT', 'USDC', 'DOGE', 'BNB'].includes(sym)) {
    return `${sym}-USD`
  }
  
  // Default to symbol as is (for US stocks)
  return sym
}

// Yahoo Finance price updating logic
const fetchYahooPrice = async (symbol) => {
  try {
    const isProd = import.meta.env.PROD
    const yhUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}?interval=1d&range=1d`
    
    // 1. If in local development, try local dev proxy first
    if (!isProd) {
      try {
        const res = await fetch(`/yahoo-finance/v8/finance/chart/${symbol}?interval=1d&range=1d`)
        if (res.ok) {
          const data = await res.json()
          return data?.chart?.result?.[0]?.meta?.regularMarketPrice ?? null
        }
      } catch {}
    }

    // 2. Sequential list of production/fallback proxies to try
    const proxies = [
      `/api/yahoo-proxy?symbol=${symbol}`,
      `https://corsproxy.io/?${encodeURIComponent(yhUrl)}`,
      `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(yhUrl)}`,
      `https://api.allorigins.win/raw?url=${encodeURIComponent(yhUrl)}`
    ]

    for (const proxyUrl of proxies) {
      try {
        const res = await fetch(proxyUrl)
        if (res.ok) {
          const data = await res.json()
          const price = data?.chart?.result?.[0]?.meta?.regularMarketPrice
          if (price !== undefined && price !== null) {
            return price
          }
        }
      } catch (e) {
        console.warn(`Proxy ${proxyUrl} failed:`, e)
      }
    }

    return null
  } catch {
    return null
  }
}

const fetchYahooPricesBatch = async (symbols) => {
  if (!symbols || symbols.length === 0) return {}
  
  const isProd = import.meta.env.PROD
  const symbolsQueryStr = symbols.join(',')
  
  // 1. Try primary batch proxy (Vercel Proxy in Prod, local dev proxy in Dev)
  const proxyUrl = isProd 
    ? `/api/yahoo-proxy?symbols=${encodeURIComponent(symbolsQueryStr)}`
    : `/yahoo-finance/v7/finance/quote?symbols=${encodeURIComponent(symbolsQueryStr)}&fields=regularMarketPrice,currency,shortName`
    
  try {
    const res = await fetch(proxyUrl)
    if (res.ok) {
      const data = await res.json()
      if (isProd) {
        if (data && data.prices) {
          return data.prices
        }
      } else {
        const prices = {}
        const quotes = data?.quoteResponse?.result ?? []
        for (const q of quotes) {
          if (q.symbol && q.regularMarketPrice != null) {
            prices[q.symbol] = q.regularMarketPrice
          }
        }
        return prices
      }
    }
  } catch (err) {
    console.warn('Batch fetch from main proxy failed, trying fallbacks:', err)
  }

  // 2. Try Fallback CORS proxies
  const yhQuoteUrl = `https://query1.finance.yahoo.com/v7/finance/quote?symbols=${encodeURIComponent(symbolsQueryStr)}&fields=regularMarketPrice,currency,shortName`
  const fallbackProxies = [
    `https://corsproxy.io/?${encodeURIComponent(yhQuoteUrl)}`,
    `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(yhQuoteUrl)}`,
    `https://api.allorigins.win/raw?url=${encodeURIComponent(yhQuoteUrl)}`
  ]

  for (const fProxy of fallbackProxies) {
    try {
      const res = await fetch(fProxy)
      if (res.ok) {
        const data = await res.json()
        const prices = {}
        const quotes = data?.quoteResponse?.result ?? []
        for (const q of quotes) {
          if (q.symbol && q.regularMarketPrice != null) {
            prices[q.symbol] = q.regularMarketPrice
          }
        }
        if (Object.keys(prices).length > 0) {
          return prices
        }
      }
    } catch (err) {
      console.warn(`Fallback proxy ${fProxy} failed:`, err)
    }
  }

  // 3. Last resort fallback: parallel single fetches
  console.warn('All batch proxies failed, executing parallel single fetches as fallback')
  const prices = {}
  const promises = symbols.map(async (sym) => {
    const price = await fetchYahooPrice(sym)
    if (price !== null) {
      prices[sym] = price
    }
  })
  await Promise.all(promises)
  return prices
}

const validateSymbol = async () => {
  const sym = newAsset.value.symbol ? newAsset.value.symbol.trim().toUpperCase() : ''
  if (!sym) {
    verificationResult.value = null
    return
  }
  
  verifyingSymbol.value = true
  verificationResult.value = { loading: true }
  
  const querySym = getYahooSymbol(sym, newAsset.value.type)
  try {
    const isProd = import.meta.env.PROD
    const yhUrl = `https://query1.finance.yahoo.com/v8/finance/chart/${querySym}?interval=1d&range=1d`
    const url = isProd 
      ? `https://api.allorigins.win/raw?url=${encodeURIComponent(yhUrl)}` 
      : `/yahoo-finance/v8/finance/chart/${querySym}?interval=1d&range=1d`
      
    const res = await fetch(url)
    if (!res.ok) {
      verificationResult.value = { success: false, msg: '查無此標的，請檢查代號' }
      verifyingSymbol.value = false
      return
    }
    const data = await res.json()
    const meta = data?.chart?.result?.[0]?.meta
    const price = meta?.regularMarketPrice
    
    if (price !== undefined && price !== null) {
      const cur = meta?.currency || (isTaiwanStock(sym) ? 'TWD' : 'USD')
      verificationResult.value = {
        success: true,
        price,
        currency: cur,
        symbol: sym
      }
      
      // Auto fill name if empty
      if (!newAsset.value.name) {
        newAsset.value.name = sym
      }
      // Auto fill buy price as current market price if empty or 0
      if (!newAsset.value.buy_price || Number(newAsset.value.buy_price) === 0) {
        newAsset.value.buy_price = price
      }
      // Auto fill custom group if empty
      if (!newAsset.value.custom_group) {
        const existingLot = investments.value.find(i => i.symbol && i.symbol.toUpperCase() === sym && i.custom_group)
        if (existingLot) {
          newAsset.value.custom_group = existingLot.custom_group
        }
      }
    } else {
      verificationResult.value = { success: false, msg: '無法取得價格，可手動輸入' }
    }
  } catch (err) {
    verificationResult.value = { success: false, msg: '驗證失敗，可直接手動輸入' }
  } finally {
    verifyingSymbol.value = false
  }
}

const refreshPrices = async () => {
  if (isRefreshing.value) return
  isRefreshing.value = true
  
  // 1. Group investments by their Yahoo symbols
  const yahooToLocalMap = {} // YahooSymbol -> { localSym, assetClass, ids: [] }
  investments.value.forEach(inv => {
    const localSym = inv.symbol.toUpperCase()
    const yhSym = getYahooSymbol(localSym, inv.asset_class)
    if (!yahooToLocalMap[yhSym]) {
      yahooToLocalMap[yhSym] = {
        localSym,
        assetClass: inv.asset_class,
        ids: []
      }
    }
    yahooToLocalMap[yhSym].ids.push(inv.id)
  })

  const yahooSymbols = Object.keys(yahooToLocalMap)
  if (yahooSymbols.length === 0) {
    isRefreshing.value = false
    return
  }

  try {
    const prices = await fetchYahooPricesBatch(yahooSymbols)
    const now = new Date().toISOString()
    const dbUpdates = []

    for (const [yhSym, price] of Object.entries(prices)) {
      if (price !== null && price !== undefined) {
        const info = yahooToLocalMap[yhSym]
        if (!info) continue

        for (const id of info.ids) {
          // Queue Supabase update
          dbUpdates.push(
            supabase
              .from('investments')
              .update({ current_price: price, price_updated_at: now })
              .eq('id', id)
          )

          // Update local reactive state immediately
          const item = investments.value.find(i => i.id === id)
          if (item) {
            item.current_price = price
            item.price_updated_at = now
          }
        }
      }
    }

    // Run Supabase updates concurrently
    if (dbUpdates.length > 0) {
      await Promise.allSettled(dbUpdates)
    }

    localStorage.setItem('local_investments', JSON.stringify(investments.value))
    await saveDailySnapshot(netWorth.value)
  } catch (error) {
    console.error('Error refreshing prices in batch:', error)
  } finally {
    isRefreshing.value = false
  }
}

// ── Accordion Handlers for Modal ──────────────────────────────────
const toggleAccordion = (category) => {
  expandedCategories.value[category] = !expandedCategories.value[category]
}

const selectSubtype = (category, subType, label) => {
  newAsset.value.category = category
  newAsset.value.type = subType
  newAsset.value.name = ''
  newAsset.value.balance = ''
  newAsset.value.symbol = ''
  newAsset.value.quantity = ''
  newAsset.value.buy_price = ''
  newAsset.value.buy_date = new Date().toISOString().split('T')[0]
  newAsset.value.custom_group = ''
  newAssetAutoRecords.value = []
  
  addModalStep.value = 2 // Move to form input step
}

const getCategoryName = (cat) => {
  switch(cat) {
    case 'liquid': return '流動資金'
    case 'invest': return '投資'
    case 'fixed': return '固定資產'
    case 'receivable': return '應收款'
    case 'liab': return '負債'
    default: return ''
  }
}

const getSubtypePlaceholder = (subType) => {
  switch (subType) {
    case 'Bank': return '例: 國泰世華、玉山銀行'
    case 'Cash': return '例: 手頭現金、緊急預備金'
    case 'E-Wallet': return '例: LINE Pay、微信錢包、支付寶'
    case 'OtherLiquid': return '例: 悠遊卡餘額、其他流動款項'
    case 'Fund': return '例: 元大美債20年、野村基金'
    case 'Stock': return '例: 台積電、特斯拉、微軟股票'
    case 'Crypto': return '例: 比特幣 BTC、乙太幣 ETH'
    case 'Metal': return '例: 黃金存摺、白銀'
    case 'OtherInvest': return '例: 實體收藏品、藝術品投資'
    case 'RealEstate': return '例: 台北大安房產、我的公寓'
    case 'Car': return '例: Honda Civic、我的汽車'
    case 'OtherFixed': return '例: 勞力士手錶、貴重樂器'
    case 'Receivable': return '例: 借小明的借款、應收專案款'
    case 'Credit Card': return '例: 富邦信用卡、台新信用卡'
    case 'Loan': return '例: 就學貸款、汽車貸款、房屋貸款'
    case 'Payable': return '例: 應付房租、分期付款'
    case 'OtherLiab': return '例: 其他借款、私人欠款'
    default: return '項目名稱'
  }
}

const addAssetItem = async () => {
  saveError.value = ''
  isSaving.value = true
  
  try {
    const generatedId = 'local-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9)
    const nowStr = new Date().toISOString()
    
    // 如果是投資類別，且需要以股票/標的模式記錄
    const isLotInvestment = ['Stock', 'Crypto', 'Fund'].includes(newAsset.value.type)
    
    if (newAsset.value.category === 'invest' && isLotInvestment) {
      if (!newAsset.value.symbol) {
        saveError.value = '請填寫股票/標的代號'
        isSaving.value = false
        return
      }
      const qty = Number(newAsset.value.quantity || 0)
      const buyPrice = Number(newAsset.value.buy_price || 0)
      
      const itemId = isEditing.value ? editingId.value : generatedId
      const excludedInvs = JSON.parse(localStorage.getItem('excluded_investments_ids') || '[]')
      if (newAsset.value.include_in_chart === false) {
        if (!excludedInvs.includes(itemId)) excludedInvs.push(itemId)
      } else {
        const idx = excludedInvs.indexOf(itemId)
        if (idx !== -1) excludedInvs.splice(idx, 1)
      }
      localStorage.setItem('excluded_investments_ids', JSON.stringify(excludedInvs))

      let customGroup = newAsset.value.custom_group || ''
      if (!isEditing.value && !customGroup && newAsset.value.symbol) {
        const symUpper = newAsset.value.symbol.toUpperCase()
        const existingLot = investments.value.find(i => i.symbol && i.symbol.toUpperCase() === symUpper && i.custom_group)
        if (existingLot) {
          customGroup = existingLot.custom_group
        }
      }

      const payload = {
        id: itemId,
        asset_class: newAsset.value.type, // Stock, Crypto, Fund
        symbol: newAsset.value.symbol.toUpperCase(),
        name: newAsset.value.name || newAsset.value.symbol.toUpperCase(),
        quantity: qty,
        average_cost: buyPrice,
        currency: newAsset.value.type === 'Stock' || newAsset.value.type === 'Crypto'
          ? (isTaiwanStock(newAsset.value.symbol) ? 'TWD' : 'USD')
          : 'TWD',
        type: 'Stock',
        current_price: buyPrice,
        buy_price: buyPrice,
        buy_date: newAsset.value.buy_date,
        created_at: isEditing.value ? (investments.value.find(i => i.id === editingId.value)?.created_at || nowStr) : nowStr,
        price_updated_at: nowStr,
        custom_group: customGroup,
        funding_account_id: newAsset.value.funding_account_id || null,
        include_in_chart: newAsset.value.include_in_chart !== false
      }
      
      let accountsChanged = false
      let updatedAccounts = [...accounts.value]
      
      if (!isEditing.value && newAsset.value.funding_account_id && syncAccountBalance.value) {
        const cost = qty * buyPrice
        const costTwd = payload.currency === 'USD' ? cost * usdTwdRate.value : cost
        
        updatedAccounts = updatedAccounts.map(acc => {
          if (acc.id === newAsset.value.funding_account_id) {
            adjustAccountBalanceByTwd(acc, -costTwd)
            if (acc.balance < 0) acc.balance = 0
            acc._dirty = true
            accountsChanged = true
          }
          return acc
        })
      }
      
      if (isEditing.value) {
        try {
          await supabase.from('investments').update({
            symbol: payload.symbol,
            name: payload.name,
            quantity: payload.quantity,
            average_cost: payload.average_cost,
            buy_price: payload.buy_price,
            buy_date: payload.buy_date,
            custom_group: payload.custom_group,
            funding_account_id: payload.funding_account_id
          }).eq('id', editingId.value)
        } catch (dbErr) {
          console.warn('Supabase DB offline, updating locally only:', dbErr)
        }
        const idx = investments.value.findIndex(i => i.id === editingId.value)
        if (idx !== -1) {
          investments.value[idx] = { ...investments.value[idx], ...payload }
        }
      } else {
        if (newAsset.value.funding_account_id) {
          todayTransactions.value.push({
            type: 'buy',
            symbol: payload.symbol,
            quantity: qty,
            price: buyPrice,
            currency: payload.currency || 'TWD',
            funding_account_id: newAsset.value.funding_account_id,
            date: payload.buy_date
          })
        }
        try {
          const dbPayload = { ...payload }
          delete dbPayload.id
          delete dbPayload.include_in_chart
          const { data, error } = await supabase.from('investments').insert([dbPayload]).select()
          if (!error && data) payload.id = data[0].id
        } catch (dbErr) {
          console.warn('Supabase DB offline, storing locally only:', dbErr)
        }
        investments.value.unshift(payload)
      }
      localStorage.setItem('local_investments', JSON.stringify(investments.value))
      
      // Save accounts changes if any funding occurred
      if (accountsChanged) {
        accounts.value = updatedAccounts
        const cleanAccounts = updatedAccounts.map(a => {
          const copy = { ...a }
          delete copy._dirty
          return copy
        })
        localStorage.setItem('local_accounts', JSON.stringify(cleanAccounts))
        
        for (const acc of updatedAccounts) {
          if (acc._dirty) {
            delete acc._dirty
            try {
              await supabase.from('accounts').update({ balance: acc.balance }).eq('id', acc.id)
            } catch (err) {
              console.warn('Sync account balance after investment funding failed:', err)
            }
          }
        }
      }
      
      // Async price fetch
      const querySym = getYahooSymbol(payload.symbol, payload.asset_class)
      fetchYahooPrice(querySym).then(async (price) => {
        if (price !== null) {
          const targetId = isEditing.value ? editingId.value : payload.id
          try {
            await supabase
              .from('investments')
              .update({ current_price: price, price_updated_at: new Date().toISOString() })
              .eq('id', targetId)
          } catch {}
          const item = investments.value.find(i => i.id === targetId)
          if (item) {
            item.current_price = price
            item.price_updated_at = new Date().toISOString()
            localStorage.setItem('local_investments', JSON.stringify(investments.value))
          }
        }
      })
    } else {
      // 流動資金、固定資產、應收款、負債，以及其他非標的類的投資 (Metal, OtherInvest 等)
      if (!newAsset.value.name || newAsset.value.balance === undefined || newAsset.value.balance === '') {
        saveError.value = '請填寫名稱與金額'
        isSaving.value = false
        return
      }
      
      const itemId = isEditing.value ? editingId.value : generatedId
      const excludedAccs = JSON.parse(localStorage.getItem('excluded_accounts_ids') || '[]')
      if (newAsset.value.include_in_chart === false) {
        if (!excludedAccs.includes(itemId)) excludedAccs.push(itemId)
      } else {
        const idx = excludedAccs.indexOf(itemId)
        if (idx !== -1) excludedAccs.splice(idx, 1)
      }
      localStorage.setItem('excluded_accounts_ids', JSON.stringify(excludedAccs))

      const payload = {
        id: itemId,
        name: newAsset.value.name,
        type: newAsset.value.type,
        balance: Math.abs(Number(newAsset.value.balance)),
        include_in_chart: newAsset.value.include_in_chart ?? true,
        remarks: newAsset.value.remarks ?? '',
        auto_record: newAssetAutoRecords.value.length > 0 ? JSON.parse(JSON.stringify(newAssetAutoRecords.value)) : null,
        created_at: isEditing.value ? (accounts.value.find(a => a.id === editingId.value)?.created_at || nowStr) : nowStr,
        custom_group: newAsset.value.custom_group || '',
        currency: newAsset.value.currency || 'TWD'
      }
      
      const dbPayload = {
        name: payload.name,
        type: payload.type,
        balance: payload.balance,
        custom_group: payload.custom_group,
        auto_record: payload.auto_record
      }
      
      if (isCurrencyColumnSupported.value) {
        dbPayload.currency = payload.currency
      }
      
      if (isEditing.value) {
        try {
          await supabase.from('accounts').update(dbPayload).eq('id', editingId.value)
        } catch (dbErr) {
          console.warn('Supabase DB offline, updating locally only:', dbErr)
        }
        const idx = accounts.value.findIndex(a => a.id === editingId.value)
        if (idx !== -1) {
          accounts.value[idx] = payload
        }
      } else {
        try {
          const { data, error } = await supabase.from('accounts').insert([dbPayload]).select()
          if (!error && data) payload.id = data[0].id
        } catch (dbErr) {
          console.warn('Supabase DB offline, storing locally only:', dbErr)
        }
        accounts.value.push(payload)
      }
      localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
    }

    showAddModal.value = false
    addModalStep.value = 1 // Reset step
    isEditing.value = false
    editingId.value = null
    expandedCategories.value = {
      liquid: true,
      invest: false,
      fixed: false,
      receivable: false,
      liab: false
    }
    
    await saveDailySnapshot(netWorth.value)
  } catch (err) {
    console.error(err)
    saveError.value = `儲存失敗：${err.message}`
  } finally {
    isSaving.value = false
  }
}

// ── CRUD Deletions ────────────────────────────────────────────────
const deleteAccount = async (id) => {
  triggerDeleteConfirm('確定要刪除此資產項目？此動作無法復原。', async () => {
    if (id && !String(id).startsWith('local-') && !String(id).startsWith('mock-')) {
      try {
        const { error } = await supabase.from('accounts').delete().eq('id', id)
        if (error) console.warn('Supabase delete account failed:', error)
      } catch (e) {
        console.warn('Supabase delete account exception:', e)
      }
    }
    
    accounts.value = accounts.value.filter(a => a.id !== id)
    localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
    await saveDailySnapshot(netWorth.value)
    
    // Close modal if we deleted the active item being edited or viewed
    if (editingId.value === id || (selectedInvestment.value && selectedInvestment.value.id === id)) {
      closeAddModal()
    }
  })
}

const deleteInvestment = async (id) => {
  triggerDeleteConfirm('確定要刪除此投資項目嗎？', async () => {
    const inv = investments.value.find(i => i.id === id)
    
    if (id && !String(id).startsWith('local-') && !String(id).startsWith('mock-')) {
      try {
        const { error } = await supabase.from('investments').delete().eq('id', id)
        if (error) console.warn('Supabase delete investment failed:', error)
      } catch (e) {
        console.warn('Supabase delete investment exception:', e)
      }
    }
    
    investments.value = investments.value.filter(i => i.id !== id)
    localStorage.setItem('local_investments', JSON.stringify(investments.value))
    await saveDailySnapshot(netWorth.value)
    
    // Close modal if we deleted the active item being edited or viewed
    if (editingId.value === id || (selectedInvestment.value && selectedInvestment.value.id === id)) {
      closeAddModal()
    }
  })
}

const deleteInvestmentBySymbol = async (symbol) => {
  if (!symbol) return
  const matching = investments.value.filter(i => i.symbol.toUpperCase() === symbol.toUpperCase())
  if (matching.length === 0) return
  
  triggerDeleteConfirm(`確定要刪除所有「${symbol}」的投資部位嗎？此動作將退回買入成本至連結的扣款帳戶。`, async () => {
    for (const inv of matching) {
      const id = inv.id
      if (id && !String(id).startsWith('local-') && !String(id).startsWith('mock-')) {
        try {
          await supabase.from('investments').delete().eq('id', id)
        } catch (e) {
          console.warn('Supabase delete investment exception:', e)
        }
      }
      
      // Refund linked funding account
      if (inv.funding_account_id) {
        const cost = Number(inv.quantity || 0) * Number(inv.buy_price || inv.average_cost || 0)
        const costTwd = inv.currency === 'USD' ? cost * usdTwdRate.value : cost
        
        accounts.value = accounts.value.map(acc => {
          if (acc.id === inv.funding_account_id) {
            acc.balance += costTwd
            if (acc.id && !String(acc.id).startsWith('local-') && !String(acc.id).startsWith('mock-')) {
              try {
                supabase.from('accounts').update({ balance: acc.balance }).eq('id', acc.id)
              } catch (dbErr) {
                console.warn('Refund funding account failed:', dbErr)
              }
            }
          }
          return acc
        })
      }
    }
    
    // Filter out all investments matching this symbol
    investments.value = investments.value.filter(i => i.symbol.toUpperCase() !== symbol.toUpperCase())
    localStorage.setItem('local_investments', JSON.stringify(investments.value))
    localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
    await saveDailySnapshot(netWorth.value)
    
    closeAddModal()
  })
}


const handleDeleteFromEdit = async () => {
  if (!isEditing.value || !editingId.value) return
  
  if (newAsset.value.category === 'invest') {
    await deleteInvestment(editingId.value)
  } else {
    await deleteAccount(editingId.value)
  }
}

// ── Helpers ───────────────────────────────────────────────────────
const formatCurrency = (amount) => {
  return new Intl.NumberFormat('zh-TW', { style: 'currency', currency: 'TWD', minimumFractionDigits: 0 }).format(amount)
}
const formatPrice = (price, currency) => {
  return currency === 'USD' 
    ? new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(price)
    : formatCurrency(price)
}
const formatDate = (dateStr) => {
  if (!dateStr) return ''
  const d = new Date(dateStr)
  return `${d.getMonth() + 1}月${d.getDate()}日`
}
const getTodayStr = () => {
  const d = new Date()
  return `${d.getMonth() + 1}月${d.getDate()}日 更新`
}

const getLastUpdatedText = (category) => {
  let dates = []
  if (category === 'invest') {
    investments.value.forEach(inv => {
      if (inv.price_updated_at) dates.push(new Date(inv.price_updated_at))
      else if (inv.created_at) dates.push(new Date(inv.created_at))
    })
  } else {
    const matched = filteredAccounts(category)
    matched.forEach(acc => {
      if (acc.updated_at) dates.push(new Date(acc.updated_at))
      else if (acc.created_at) dates.push(new Date(acc.created_at))
    })
  }
  
  if (dates.length === 0) {
    const today = new Date()
    return `${today.getMonth() + 1}月${today.getDate()}日 更新`
  }
  
  const maxDate = new Date(Math.max(...dates.map(d => d.getTime())))
  return `${maxDate.getMonth() + 1}月${maxDate.getDate()}日 更新`
}

const isTaiwanStock = (symbol) => {
  if (!symbol) return false
  const sym = symbol.trim().toUpperCase()
  return sym.endsWith('.TW') || /^\d{4,5}$/.test(sym)
}

const formatInvestCurrency = (amount, currency = 'TWD') => {
  const formatted = new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  }).format(amount)
  return formatted.replace(/^[A-Z$]+/, (match) => match + ' ')
}

const formatHistoryValue = (amount, currency = 'TWD') => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: currency,
    minimumFractionDigits: 0,
    maximumFractionDigits: 0
  }).format(amount)
}

const formatDateDetailed = (dateStr) => {
  if (!dateStr) return ''
  const d = new Date(dateStr)
  const hour = d.getHours()
  const min = d.getMinutes().toString().padStart(2, '0')
  const ampm = hour >= 12 ? '下午' : '上午'
  const displayHour = hour % 12 || 12
  return `${d.getFullYear()}/${d.getMonth() + 1}/${d.getDate()} ${ampm} ${displayHour}:${min}`
}

const formatInvestNumber = (num) => {
  if (num === undefined || num === null) return '0'
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(num)
}

const translateTypeSettings = (type) => {
  switch (type) {
    case 'Bank': return '銀行帳戶'
    case 'Cash': return '現金'
    case 'E-Wallet': return '電子錢包'
    case 'OtherLiquid': return '其他流動資金'
    case 'RealEstate': return '房產'
    case 'Car': return '汽車'
    case 'OtherFixed': return '其他固定資產'
    case 'Receivable': return '應收款項'
    case 'Credit Card': return '信用卡帳單'
    case 'Loan': return '貸款債務'
    case 'Payable': return '應付款項'
    case 'OtherLiab': return '其他負債'
    // Investments
    case 'Fund': return '投資基金'
    case 'Stock': return '股票'
    case 'Crypto': return '加密貨幣'
    case 'Metal': return '貴金屬'
    case 'OtherInvest': return '其他投資'
    default: return type
  }
}

const getCategoryThemeColor = (category) => {
  switch (category) {
    case 'liquid': return '#2ebd59'
    case 'invest': return '#5c67f5'
    case 'fixed': return '#3a59cc'
    case 'receivable': return '#8ba4e8'
    case 'liab': return '#ccd7f5'
    default: return '#5c67f5'
  }
}

const getCategoryBtnTextColor = (category) => {
  if (['receivable', 'liab'].includes(category)) return '#121212'
  return '#ffffff'
}

const getTypeIconAndColor = (type) => {
  switch (type) {
    case 'Bank': return { icon: PhCreditCard, color: 'text-green' }
    case 'Cash': return { icon: PhWallet, color: 'text-green' }
    case 'E-Wallet': return { icon: PhCloudArrowUp, color: 'text-green' }
    case 'OtherLiquid': return { icon: PhCards, color: 'text-green' }
    case 'Fund': return { icon: PhCurrencyCny, color: 'text-purple' }
    case 'Stock': return { icon: PhChartBar, color: 'text-purple' }
    case 'Crypto': return { icon: PhCurrencyBtc, color: 'text-purple' }
    case 'Metal': return { icon: PhCube, color: 'text-purple' }
    case 'OtherInvest': return { icon: PhLeaf, color: 'text-purple' }
    case 'RealEstate': return { icon: PhBuildings, color: 'text-blue' }
    case 'Car': return { icon: PhCar, color: 'text-blue' }
    case 'OtherFixed': return { icon: PhLock, color: 'text-blue' }
    case 'Receivable': return { icon: PhUsers, color: 'text-light-blue' }
    case 'Credit Card': return { icon: PhCreditCard, color: 'text-gray-blue' }
    case 'Loan': return { icon: PhBank, color: 'text-gray-blue' }
    case 'Payable': return { icon: PhCreditCard, color: 'text-gray-blue' }
    case 'OtherLiab': return { icon: PhCreditCard, color: 'text-gray-blue' }
    default: return { icon: PhWallet, color: 'text-green' }
  }
}

const openSubList = (type) => {
  subListType.value = type
  addModalStep.value = 1.5
}

const closeAddModal = () => {
  showAddModal.value = false
  addModalStep.value = 1
  isEditing.value = false
  editingId.value = null
  syncAccountBalance.value = false
  customProfitVal.value = ''
}

const selectProvider = (item) => {
  if (subListType.value === 'E-Wallet') newAsset.value.category = 'liquid'
  else if (subListType.value === 'Stock') newAsset.value.category = 'invest'
  else if (subListType.value === 'OtherInvest') newAsset.value.category = 'invest'
  else if (subListType.value === 'Loan') newAsset.value.category = 'liab'

  newAsset.value.type = item.type
  newAsset.value.name = item.label
  newAsset.value.balance = ''
  newAsset.value.symbol = ''
  newAsset.value.quantity = ''
  newAsset.value.buy_price = ''
  newAsset.value.buy_date = new Date().toISOString().split('T')[0]
  newAsset.value.custom_group = ''
  newAsset.value.funding_account_id = null
  
  newAsset.value.include_in_chart = true
  newAsset.value.remarks = ''
  newAsset.value.auto_record = null
  newAsset.value.currency = 'TWD'
  newAssetAutoRecords.value = []
  verificationResult.value = null

  addModalStep.value = 2
}

const subListTitle = computed(() => {
  switch (subListType.value) {
    case 'E-Wallet': return '電子錢包'
    case 'Stock': return '股票'
    case 'OtherInvest': return '其他投資'
    case 'Loan': return '貸款'
    default: return ''
  }
})

const subListOptions = computed(() => {
  switch (subListType.value) {
    case 'E-Wallet':
      return [
        { label: 'LINE Pay', type: 'E-Wallet', icon: PhWallet, colorClass: 'text-green' },
        { label: 'Apple Pay', type: 'E-Wallet', icon: PhAppleLogo, colorClass: 'text-green' },
        { label: '街口支付', type: 'E-Wallet', icon: PhWallet, colorClass: 'text-green' },
        { label: '微信錢包', type: 'E-Wallet', icon: PhWechatLogo, colorClass: 'text-green' },
        { label: '支付寶', type: 'E-Wallet', icon: PhQrCode, colorClass: 'text-green' },
        { label: '眾安銀行', type: 'E-Wallet', icon: PhBank, colorClass: 'text-green' },
        { label: 'Paypal', type: 'E-Wallet', icon: PhCreditCard, colorClass: 'text-green' },
        { label: '其他電子錢包', type: 'E-Wallet', icon: PhCards, colorClass: 'text-green' }
      ]
    case 'Stock':
      return [
        { label: '美股', type: 'Stock', icon: PhChartBar, colorClass: 'text-purple' },
        { label: '台股', type: 'Stock', icon: PhChartBar, colorClass: 'text-purple' },
        { label: '港股', type: 'Stock', icon: PhChartBar, colorClass: 'text-purple' },
        { label: '其他股票', type: 'Stock', icon: PhChartBar, colorClass: 'text-purple' }
      ]
    case 'OtherInvest':
      return [
        { label: '實體收藏品', type: 'OtherInvest', icon: PhLeaf, colorClass: 'text-purple' },
        { label: '藝術品', type: 'OtherInvest', icon: PhLeaf, colorClass: 'text-purple' },
        { label: '其他', type: 'OtherInvest', icon: PhLeaf, colorClass: 'text-purple' }
      ]
    case 'Loan':
      return [
        { label: '房屋貸款', type: 'Loan', icon: PhBank, colorClass: 'text-gray-blue' },
        { label: '汽車貸款', type: 'Loan', icon: PhCar, colorClass: 'text-gray-blue' },
        { label: '就學貸款', type: 'Loan', icon: PhBookOpen, colorClass: 'text-gray-blue' },
        { label: '個人信用貸款', type: 'Loan', icon: PhUser, colorClass: 'text-gray-blue' },
        { label: '其他貸款', type: 'Loan', icon: PhBank, colorClass: 'text-gray-blue' }
      ]
    default:
      return []
  }
})

const processAutoRecords = async () => {
  const today = new Date()
  const currentYear = today.getFullYear()
  const currentMonth = today.getMonth()
  const currentDay = today.getDate()
  
  let changed = false
  const updatedAccounts = [...accounts.value]
  
  for (let i = 0; i < updatedAccounts.length; i++) {
    const acc = updatedAccounts[i]
    if (acc.auto_record) {
      // 標準化為陣列處理，相容舊有單一物件格式
      let records = []
      if (Array.isArray(acc.auto_record)) {
        records = acc.auto_record
      } else if (acc.auto_record.enabled) {
        records = [acc.auto_record]
      }
      
      let recordChanged = false
      for (const ar of records) {
        if (!ar.enabled) continue
        
        // Expiry check
        if (ar.expiry === 'custom' && ar.expiry_date) {
          const expDate = new Date(ar.expiry_date + 'T23:59:59')
          const recordDate = new Date(currentYear, currentMonth, Number(ar.day || 1))
          if (recordDate > expDate) {
            continue
          }
        }
        
        const day = Number(ar.day || 1)
        const lastDayOfCurrentMonth = new Date(currentYear, currentMonth + 1, 0).getDate()
        const effectiveDay = Math.min(day, lastDayOfCurrentMonth)
        
        let lastProcessedYear = 0
        let lastProcessedMonth = -1
        
        if (ar.last_processed_date) {
          const lpd = new Date(ar.last_processed_date)
          lastProcessedYear = lpd.getFullYear()
          lastProcessedMonth = lpd.getMonth()
        }
        
        const isCurrentMonthProcessed = (lastProcessedYear === currentYear && lastProcessedMonth === currentMonth)
        
        if (currentDay >= effectiveDay && !isCurrentMonthProcessed) {
          const amount = Number(ar.amount || 0)
          const type = ar.type
          const arCurrency = ar.currency || 'TWD'
          
          let amountTwd = amount
          if (arCurrency === 'USD') {
            amountTwd = amount * usdTwdRate.value
          } else if (arCurrency === 'JPY') {
            amountTwd = amount * (jpyTwdRate.value || 0.22)
          }
          amountTwd = Math.round(amountTwd)
          
          if (type === 'income') {
            adjustAccountBalanceByTwd(acc, amountTwd)
            showToast(`自動記帳：${acc.name} 固定收入 ${arCurrency} ${amount}`)
          } else if (type === 'expense') {
            adjustAccountBalanceByTwd(acc, -amountTwd)
            if (acc.balance < 0) acc.balance = 0
            showToast(`自動記帳：${acc.name} 固定支出 ${arCurrency} ${amount}`)
          } else if (type === 'transfer') {
            const targetAcc = updatedAccounts.find(a => a.id === ar.target_account_id)
            if (targetAcc) {
              adjustAccountBalanceByTwd(acc, -amountTwd)
              if (acc.balance < 0) acc.balance = 0
              
              // 如果轉入的目標帳戶是負債類（如：房貸、信貸、信用卡），轉帳代表還款，應減少負債餘額
              const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
              if (liabTypes.includes(targetAcc.type)) {
                // 如果設定了年利率，先算利息支出，剩下的才是還本金
                if (ar.interest_rate && Number(ar.interest_rate) > 0) {
                  const targetBalanceTwd = getAccountBalanceTwd(targetAcc)
                  const rate = Number(ar.interest_rate)
                  const monthlyInterestTwd = Math.round(targetBalanceTwd * (rate / 100) / 12)
                  const principalPaidTwd = Math.max(0, amountTwd - monthlyInterestTwd)
                  
                  adjustAccountBalanceByTwd(targetAcc, -principalPaidTwd)
                  if (targetAcc.balance < 0) targetAcc.balance = 0
                  
                  showToast(`自動還款：${acc.name} ➡️ ${targetAcc.name} (本金 -${principalPaidTwd}, 利息 -${monthlyInterestTwd})`)
                } else {
                  adjustAccountBalanceByTwd(targetAcc, -amountTwd)
                  if (targetAcc.balance < 0) targetAcc.balance = 0
                  showToast(`自動轉帳：從 ${acc.name} 轉帳至 ${targetAcc.name} ${arCurrency} ${amount}`)
                }
              } else {
                adjustAccountBalanceByTwd(targetAcc, amountTwd)
                showToast(`自動轉帳：從 ${acc.name} 轉帳至 ${targetAcc.name} ${arCurrency} ${amount}`)
              }
              
              targetAcc._dirty = true
            } else {
              console.warn(`Target account ${ar.target_account_id} not found for transfer`)
            }
          } else if (type === 'dca_invest') {
            // Postpone execution to next workday if it's weekend (Saturday or Sunday)
            const dayOfWeek = today.getDay()
            if (dayOfWeek === 0 || dayOfWeek === 6) {
              continue // Skip this auto record execution for today, try again tomorrow
            }

            const arCurrency = ar.currency || 'TWD'
            const deductTwd = Math.round(arCurrency === 'USD' ? amount * (usdTwdRate.value || 30) : amount)
            adjustAccountBalanceByTwd(acc, -deductTwd)
            if (acc.balance < 0) acc.balance = 0
            
            const symbol = (ar.symbol || '').trim().toUpperCase()
            if (symbol) {
              const querySym = getYahooSymbol(symbol, /^\d{4,6}$/.test(symbol) ? 'tw_stock' : 'stock')
              const price = await fetchYahooPrice(querySym)
              if (price !== null && price > 0) {
                const isUsdStock = !(/^\d{4,6}$/.test(symbol) || symbol.endsWith('.TW') || symbol.endsWith('.TWO'))
                
                let quantity = 0
                if (arCurrency === 'USD') {
                  quantity = Number((amount / price).toFixed(6))
                } else {
                  quantity = isUsdStock 
                    ? Number(((amount / (usdTwdRate.value || 30)) / price).toFixed(6))
                    : Number((amount / price).toFixed(6))
                }
                  
                const nowStr = new Date().toISOString()
                const generatedId = 'local-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9)
                
                const existingGroup = investments.value.find(
                  i => i.symbol && i.symbol.toUpperCase() === symbol.toUpperCase() && i.custom_group
                )?.custom_group

                const payload = {
                  id: generatedId,
                  asset_class: /^\d{4,6}$/.test(symbol) ? 'tw_stock' : 'stock',
                  symbol: symbol,
                  name: symbol,
                  quantity: quantity,
                  average_cost: price,
                  currency: isUsdStock ? 'USD' : 'TWD',
                  type: 'DCA',
                  current_price: price,
                  buy_price: price,
                  buy_date: today.toISOString().split('T')[0],
                  created_at: nowStr,
                  price_updated_at: nowStr,
                  funding_account_id: acc.id,
                  custom_group: existingGroup || '',
                  include_in_chart: true
                }
                
                try {
                  const dbPayload = { ...payload }
                  delete dbPayload.id
                  delete dbPayload.include_in_chart
                  const { data, error } = await supabase.from('investments').insert([dbPayload]).select()
                  if (!error && data) {
                    payload.id = data[0].id
                  }
                } catch (dbErr) {
                  console.warn('Sync DCA investment to DB failed:', dbErr)
                }
                
                investments.value.unshift(payload)
                localStorage.setItem('local_investments', JSON.stringify(investments.value))
                showToast(`定期買股：${acc.name} 扣款 ${arCurrency} ${amount} 購入 ${symbol} (${quantity} 股, 單價 ${price})`)
              } else {
                showToast(`定期買股：${acc.name} 扣款 ${arCurrency} ${amount}，但無法獲取 ${symbol} 的股價，請手動確認。`)
              }
            } else {
              showToast(`定期買股：${acc.name} 扣款 ${arCurrency} ${amount}，但未設定股票代號。`)
            }
          }
          
          ar.last_processed_date = today.toISOString()
          recordChanged = true
          changed = true
        }
      }
      
      if (recordChanged) {
        acc._dirty = true
      }
    }
  }
  
  if (changed) {
    const cleanAccounts = updatedAccounts.map(a => {
      const copy = { ...a }
      delete copy._dirty
      return copy
    })
    accounts.value = updatedAccounts
    localStorage.setItem('local_accounts', JSON.stringify(cleanAccounts))
    await saveDailySnapshot(netWorth.value)
    
    // Sync dirty accounts back to Supabase
    for (const acc of updatedAccounts) {
      if (acc._dirty) {
        delete acc._dirty
        try {
          await supabase.from('accounts').update({ balance: acc.balance, auto_record: acc.auto_record }).eq('id', acc.id)
        } catch (err) {
          console.warn('Sync auto-record balance failed:', err)
        }
      }
    }
  }
}

// ── Custom Group Management ──────────────────────────────────────
const customAccountGroupsList = ref(JSON.parse(localStorage.getItem('custom_account_groups') || '[]'))
const customInvestGroupsList = ref(JSON.parse(localStorage.getItem('custom_invest_groups') || '[]'))

const activeGroupType = ref('account') // 'account' or 'invest'

const investGroupsExpanded = ref({})

const toggleInvestGroup = (groupName) => {
  if (investGroupsExpanded.value[groupName] === undefined) {
    investGroupsExpanded.value[groupName] = false // Collapse if currently default expanded
  } else {
    investGroupsExpanded.value[groupName] = !investGroupsExpanded.value[groupName]
  }
}

const isInvestGroupExpanded = (groupName) => {
  return investGroupsExpanded.value[groupName] !== false
}


const syncGroups = () => {
  // 取得自訂群組，預設改為空陣列
  let localAccountGroups = JSON.parse(localStorage.getItem('custom_account_groups') || '[]')
  let localInvestGroups = JSON.parse(localStorage.getItem('custom_invest_groups') || '[]')
  
  // 舊的預設群組：如果使用者沒有在使用，我們就自動過濾掉
  const defaultAccountNames = ["流動資產", "固定資產"]
  const defaultInvestNames = ["台股", "美股"]
  
  localAccountGroups = localAccountGroups.filter(g => !defaultAccountNames.includes(g))
  localInvestGroups = localInvestGroups.filter(g => !defaultInvestNames.includes(g))
  
  // 遷移歷史因選單顛倒導致儲存位置顛倒的自訂群組資料
  const investKeywords = ["台股", "美股", "投資", "股票", "證券", "基金"]
  const accountKeywords = ["流動資產", "固定資產", "銀行", "現金", "負債"]
  
  const toMoveToInvest = localAccountGroups.filter(g => investKeywords.some(kw => g.includes(kw)))
  const toMoveToAccount = localInvestGroups.filter(g => accountKeywords.some(kw => g.includes(kw)))
  
  if (toMoveToInvest.length > 0 || toMoveToAccount.length > 0) {
    localAccountGroups = localAccountGroups.filter(g => !toMoveToInvest.includes(g)).concat(toMoveToAccount)
    localInvestGroups = localInvestGroups.filter(g => !toMoveToAccount.includes(g)).concat(toMoveToInvest)
  }

  const dbAccountGroups = new Set()
  const dbInvestGroups = new Set()
  
  if (Array.isArray(accounts.value)) {
    accounts.value.forEach(a => { if (a.custom_group && a.custom_group.trim()) dbAccountGroups.add(a.custom_group.trim()) })
  }
  if (Array.isArray(investments.value)) {
    investments.value.forEach(i => { if (i.custom_group && i.custom_group.trim()) dbInvestGroups.add(i.custom_group.trim()) })
  }
  
  // 合併自訂群組與資料庫中實際有在使用的群組（避免刪除正在使用的群組）
  const mergedAccount = Array.from(new Set([...localAccountGroups, ...dbAccountGroups]))
  localStorage.setItem('custom_account_groups', JSON.stringify(mergedAccount))
  customAccountGroupsList.value = mergedAccount

  const mergedInvest = Array.from(new Set([...localInvestGroups, ...dbInvestGroups]))
  localStorage.setItem('custom_invest_groups', JSON.stringify(mergedInvest))
  customInvestGroupsList.value = mergedInvest
}

const getGroupMemberCount = (groupName, type) => {
  return getGroupMembers(groupName, type).length
}

const getGroupMembers = (groupName, type) => {
  if (type === 'account') {
    return (accounts.value || []).filter(a => a.custom_group === groupName).map(a => ({ id: a.id, name: a.name, type: 'account' }))
  } else {
    return (investments.value || []).filter(i => i.custom_group === groupName).map(i => ({ id: i.id, name: `${i.symbol} (${i.name || ''})`, type: 'investment' }))
  }
}

const deleteGroup = (groupName, type) => {
  triggerDeleteConfirm(`確定要刪除群組「${groupName}」嗎？群組內的資產與投資將設為無群組，不會刪除實際資料。`, async () => {
    if (type === 'account') {
      accounts.value = accounts.value.map(a => {
        if (a.custom_group === groupName) {
          a.custom_group = ''
          if (a.id && !String(a.id).startsWith('local-') && !String(a.id).startsWith('mock-')) {
            supabase.from('accounts').update({ custom_group: '' }).eq('id', a.id)
          }
        }
        return a
      })
      localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
      customAccountGroupsList.value = customAccountGroupsList.value.filter(g => g !== groupName)
      localStorage.setItem('custom_account_groups', JSON.stringify(customAccountGroupsList.value))
    } else {
      investments.value = investments.value.map(i => {
        if (i.custom_group === groupName) {
          i.custom_group = ''
          if (i.id && !String(i.id).startsWith('local-') && !String(i.id).startsWith('mock-')) {
            supabase.from('investments').update({ custom_group: '' }).eq('id', i.id)
          }
        }
        return i
      })
      localStorage.setItem('local_investments', JSON.stringify(investments.value))
      customInvestGroupsList.value = customInvestGroupsList.value.filter(g => g !== groupName)
      localStorage.setItem('custom_invest_groups', JSON.stringify(customInvestGroupsList.value))
    }
  })
}

// Create Group State
const showCreateGroupModal = ref(false)
const newGroupName = ref('')

const openCreateGroupModal = (type) => {
  activeGroupType.value = type
  newGroupName.value = ''
  showCreateGroupModal.value = true
}

const submitCreateGroup = () => {
  const name = newGroupName.value.trim()
  if (!name) return
  const list = activeGroupType.value === 'account' ? customAccountGroupsList : customInvestGroupsList
  if (list.value.includes(name)) {
    alert('群組名稱已存在')
    return
  }
  list.value.push(name)
  localStorage.setItem(activeGroupType.value === 'account' ? 'custom_account_groups' : 'custom_invest_groups', JSON.stringify(list.value))
  showCreateGroupModal.value = false
}

// Manage Group Modal State
const showManageGroupModal = ref(false)
const selectedGroupToManage = ref('')
const selectedItemsToAddToGroup = ref([]) // Array of selected JSON string representations

const manageGroup = (groupName, type) => {
  activeGroupType.value = type
  selectedGroupToManage.value = groupName
  selectedItemsToAddToGroup.value = []
  showManageGroupModal.value = true
}

const getAvailableItemsForGroup = computed(() => {
  if (activeGroupType.value === 'account') {
    return (accounts.value || []).filter(a => a.custom_group !== selectedGroupToManage.value).map(a => ({ id: a.id, name: `🏦 ${a.name} (${translateTypeSettings(a.type)})`, type: 'account' }))
  } else {
    return (investments.value || []).filter(i => i.custom_group !== selectedGroupToManage.value).map(i => ({ id: i.id, name: `📈 ${i.symbol} (${i.name || ''})`, type: 'investment' }))
  }
})

const addSelectedItemsToGroup = async () => {
  if (selectedItemsToAddToGroup.value.length === 0) return
  
  const parsedItems = selectedItemsToAddToGroup.value.map(jsonStr => JSON.parse(jsonStr))
  const accountIds = parsedItems.filter(item => item.type === 'account').map(item => item.id)
  const investmentIds = parsedItems.filter(item => item.type === 'investment').map(item => item.id)

  if (accountIds.length > 0) {
    accounts.value = accounts.value.map(a => {
      if (accountIds.includes(a.id)) {
        a.custom_group = selectedGroupToManage.value
      }
      return a
    })
    localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
    
    const dbAccountIds = accountIds.filter(id => !String(id).startsWith('local-') && !String(id).startsWith('mock-'))
    if (dbAccountIds.length > 0) {
      await Promise.all(dbAccountIds.map(id => 
        supabase.from('accounts').update({ custom_group: selectedGroupToManage.value }).eq('id', id)
      ))
    }
  }

  if (investmentIds.length > 0) {
    investments.value = investments.value.map(i => {
      if (investmentIds.includes(i.id)) {
        i.custom_group = selectedGroupToManage.value
      }
      return i
    })
    localStorage.setItem('local_investments', JSON.stringify(investments.value))
    
    const dbInvestmentIds = investmentIds.filter(id => !String(id).startsWith('local-') && !String(id).startsWith('mock-'))
    if (dbInvestmentIds.length > 0) {
      await Promise.all(dbInvestmentIds.map(id => 
        supabase.from('investments').update({ custom_group: selectedGroupToManage.value }).eq('id', id)
      ))
    }
  }
  
  selectedItemsToAddToGroup.value = []
}

const removeItemFromGroup = async (id, type) => {
  if (type === 'account') {
    accounts.value = accounts.value.map(a => {
      if (a.id === id) {
        a.custom_group = ''
      }
      return a
    })
    localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
    if (id && !String(id).startsWith('local-') && !String(id).startsWith('mock-')) {
      await supabase.from('accounts').update({ custom_group: '' }).eq('id', id)
    }
  } else {
    investments.value = investments.value.map(i => {
      if (i.id === id) i.custom_group = ''
      return i
    })
    localStorage.setItem('local_investments', JSON.stringify(investments.value))
    if (id && !String(id).startsWith('local-') && !String(id).startsWith('mock-')) {
      await supabase.from('investments').update({ custom_group: '' }).eq('id', id)
    }
  }
}

// ── 數據維護與重置 ──────────────────────────────────────────────────
const clearNetWorthHistory = () => {
  triggerDeleteConfirm('確定要清空所有歷史淨資產紀錄嗎？此動作將無法還原，且趨勢圖將重新以目前的淨資產開始累積。', async () => {
    localStorage.removeItem('net_worth_history')
    try {
      const { error } = await supabase.from('net_worth_history').delete().neq('amount', -999999)
      if (error) console.warn('Supabase clear history failed:', error)
    } catch (e) {
      console.warn('Supabase clear history exception:', e)
    }
    historyRecords.value = []
    await saveDailySnapshot(netWorth.value)
    await fetchHistoryData()
    showToast('歷史淨資產紀錄已成功重置')
  })
}


let focusListener = null
let visibilityListener = null

onMounted(() => {
  // 檢查資料庫是否支援 accounts 欄位中的 currency 欄位
  supabase.from('accounts').select('currency').limit(1).then(({ error }) => {
    isCurrencyColumnSupported.value = !error
  })
  
  fetchAllData()
  
  focusListener = () => {
    fetchAllData()
  }
  window.addEventListener('focus', focusListener)
  
  visibilityListener = () => {
    if (document.visibilityState === 'visible') {
      fetchAllData()
    }
  }
  window.addEventListener('visibilitychange', visibilityListener)
})

onActivated(() => {
  fetchAllData()
})

onUnmounted(() => {
  if (focusListener) {
    window.removeEventListener('focus', focusListener)
  }
  if (visibilityListener) {
    window.removeEventListener('visibilitychange', visibilityListener)
  }
})
</script>

<template>
  <div class="dashboard-container" v-if="isInitialDataLoaded" :style="{ backgroundColor: 'var(--color-bg)' }">
    
    <!-- Toast Notification -->
    <div v-if="toastMessage" class="app-toast">
      <PhCheckCircle size="20" weight="bold" style="color: #2ebd59;" />
      <span>{{ toastMessage }}</span>
    </div>

    <Transition name="fade-tab" mode="out-in">
      <!-- ── 1. 資產清單視圖 (List Tab) ────────────────────────────────── -->
      <div v-if="currentTab === 'list'" key="list" class="tab-view-content" :style="{ backgroundColor: 'var(--color-bg)', padding: isTreeView ? '1.5rem 1.25rem' : '1.5rem 1.25rem 120px 1.25rem' }">
      
      <!-- Case 1: Tree View -->
      <template v-if="isTreeView">
        <!-- Top Balance Header -->
        <div class="top-balance-header" style="margin-bottom: 1rem;">
          <div class="balance-row" style="align-items: center; margin-top: 0; width: 100%;">
            <span class="balance-title" style="font-size: 1.5rem; font-weight: 800; color: var(--color-text);">資產分配比</span>
            <!-- Caret right in circle button matches the screenshot -->
            <button class="nav-back-circle" @click="isTreeView = false" title="返回列表" style="background: rgba(0, 0, 0, 0.05); color: var(--color-text); width: 36px; height: 36px;">
              <PhCaretRight size="20" weight="bold" />
            </button>
          </div>
        </div>

        <!-- Treemap / Allocation Blocks representation -->
        <div class="treemap-container">
          <!-- Left Column (Liabilities & Spacer) -->
          <div v-if="liabPct > 0" class="treemap-column treemap-left">
            <div class="treemap-spacer" :style="{ flex: 100 - liabPct }"></div>
            <div class="treemap-block block-liab-val" :class="{ 'layout-inline': liabPct < 15 }" :style="{ flex: liabPct }">
              <span class="block-pct">{{ liabPct }}%</span>
              <span class="block-name">負債</span>
            </div>
          </div>
          
          <!-- Right Column (Stacked Positive Assets) -->
          <div class="treemap-column" :class="liabPct > 0 ? 'treemap-right' : 'treemap-full'">
            <div v-if="investPct > 0" class="treemap-block block-invest-val" :class="{ 'layout-inline': investPct < 15 }" :style="{ flex: investPct }">
              <span class="block-pct">{{ investPct }}%</span>
              <span class="block-name">投資</span>
            </div>
            <div v-if="liquidPct > 0" class="treemap-block block-liquid-val" :class="{ 'layout-inline': liquidPct < 15 }" :style="{ flex: liquidPct }">
              <span class="block-pct">{{ liquidPct }}%</span>
              <span class="block-name">流動資金</span>
            </div>
            <div v-if="fixedPct > 0" class="treemap-block block-fixed-val" :class="{ 'layout-inline': fixedPct < 15 }" :style="{ flex: fixedPct }">
              <span class="block-pct">{{ fixedPct }}%</span>
              <span class="block-name">固定資產</span>
            </div>
            <div v-if="receivablePct > 0" class="treemap-block block-receivable-val" :class="{ 'layout-inline': receivablePct < 15 }" :style="{ flex: receivablePct }">
              <span class="block-pct">{{ receivablePct }}%</span>
              <span class="block-name">應收款</span>
            </div>
            <div v-if="totalPositiveAssets === 0" class="treemap-block" style="flex: 1; background: var(--color-card-bg); border: 2px dashed var(--color-card-border); color: var(--color-text-muted); justify-content: center; align-items: center; font-weight: 500;">
              <span>無資產分配數據</span>
            </div>
          </div>
        </div>
      </template>

      <!-- Case 2: Standard List View -->
      <template v-else>
        <!-- Top Balance Header -->
        <div class="top-balance-header">
          <div class="balance-left">
            <span class="balance-title">我的淨資產 (TWD)</span>
            <button @click="togglePrivacy" class="privacy-btn">
              <component :is="isHidden ? PhEyeSlash : PhEye" size="18" />
            </button>
          </div>
          <div class="balance-row">
            <span class="balance-amount">{{ isHidden ? '••••••' : formatCurrency(netWorth).replace('$', '') }}</span>
            <div style="display: flex; gap: 10px; align-items: center;">
              <!-- Manual database sync button -->
              <button class="nav-back-circle" @click="handleSyncAll" :disabled="isSyncingData || isRefreshing" title="手動同步" style="background: rgba(0,0,0,0.03); color: var(--color-text); width: 36px; height: 36px; display: flex; align-items: center; justify-content: center; border: none; cursor: pointer; border-radius: 50%;">
                <PhArrowClockwise size="20" :class="{ spin: isSyncingData || isRefreshing }" weight="bold" />
              </button>
              <!-- Circle button with > caret to switch to tree view -->
              <button class="nav-back-circle" @click="isTreeView = true" title="查看資產分配比" style="background: rgba(0,0,0,0.03); color: var(--color-text); width: 36px; height: 36px;">
                <PhCaretRight size="20" weight="bold" />
              </button>
              <button class="add-circular-btn" @click="showAddModal = true; addModalStep = 1" title="新增項目">
                <PhPlus size="20" weight="bold" />
              </button>
            </div>
          </div>
        </div>

        <!-- Main Layout: Sidebar distribution progress bar + Cards -->
        <div class="main-layout">
          <!-- Vertical Accent Distribution Bar -->
          <div class="left-bar-container">
            <div class="bar-segment segment-liquid" :style="{ height: liquidBarPct + '%' }" title="流動資金"></div>
            <div class="bar-segment segment-invest" :style="{ height: investBarPct + '%' }" title="投資"></div>
            <div class="bar-segment segment-fixed" :style="{ height: fixedBarPct + '%' }" title="固定資產"></div>
            <div class="bar-segment segment-receivable" :style="{ height: receivableBarPct + '%' }" title="應收款"></div>
          </div>

          <!-- Right: Cards Column -->
          <div class="list-column">
            
            <!-- Card: 流動資金 -->
            <div class="group-wrapper" v-if="filteredAccounts('liquid').length > 0 || accounts.length === 0">
              <div class="group-header-card" :class="{ 'expanded-header bg-liquid': listExpanded.liquid }" @click="toggleListExpand('liquid')" style="cursor: pointer;">
                <div class="card-header-main-row">
                  <span class="group-title-text" :class="{ 'text-dark': !listExpanded.liquid, 'text-white': listExpanded.liquid }">流動資金</span>
                  <span class="group-value-text" :class="{ 'text-dark': !listExpanded.liquid, 'text-white': listExpanded.liquid }">{{ isHidden ? '••••••' : formatCurrency(totalLiquidAssets).replace('$', '') }}</span>
                </div>
                <div class="card-header-sub-row" v-if="!listExpanded.liquid">
                  <div class="card-subtitle-col">
                    <span class="group-desc-subtitle">{{ liquidSubtitle }}</span>
                    <div class="three-dots-handle">
                      <span class="dot"></span>
                      <span class="dot"></span>
                      <span class="dot"></span>
                    </div>
                  </div>
                  <span class="group-update-date">{{ getLastUpdatedText('liquid') }}</span>
                </div>
              </div>
              
              <div class="collapsible-wrapper" :class="{ expanded: listExpanded.liquid }">
                <div class="collapsible-content">
                  <div class="group-body">
                    <div v-if="getCategoryFlatList('liquid').length > 0" class="group-card-expanded-list" style="display: flex; flex-direction: column; gap: 4px; padding-bottom: 8px;">
                      <div v-for="item in getCategoryFlatList('liquid')" :key="item.isGroup ? 'g-' + item.name : 'a-' + item.rawItem.id" class="sub-item-card" @click.stop="item.isGroup ? openCustomGroupDetail(item.name, 'liquid') : editAccount(item.rawItem)" style="cursor: pointer;">
                        <!-- Circular Percentage Badge -->
                        <div class="sub-item-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; font-weight: 800;">
                          {{ Math.round(item.percentage) }}%
                        </div>
                        
                        <!-- Details -->
                        <div class="sub-item-info">
                          <template v-if="item.isGroup">
                            <div class="sub-item-name">{{ item.name }}</div>
                            <div class="sub-item-desc">{{ item.desc }}</div>
                          </template>
                          <template v-else>
                            <div style="display: flex; align-items: center; gap: 6px;">
                              <component :is="getTypeIconAndColor(item.rawItem.type).icon" :style="{ color: getTypeIconAndColor(item.rawItem.type).color }" size="16" weight="duotone" />
                              <span class="sub-item-name" style="font-weight: 600; color: var(--color-text);">{{ item.name }}</span>
                            </div>
                            <div class="sub-item-desc">
                              {{ item.desc }}
                              <span v-if="item.rawItem.currency && item.rawItem.currency !== 'TWD'" style="color: var(--color-text-muted); opacity: 0.8; margin-left: 6px; font-weight: 600;">
                                ({{ item.rawItem.currency }} {{ formatInvestNumber(item.rawItem.balance) }})
                              </span>
                            </div>
                          </template>
                        </div>

                        <!-- Value & Date -->
                        <div class="sub-item-right">
                          <div class="sub-item-val">
                            {{ isHidden ? '••••••' : formatCurrency(item.balance).replace('$', '') }}
                          </div>
                          <div class="sub-item-date" style="display: flex; align-items: center; gap: 4px; justify-content: flex-end;">
                            <span>{{ item.isGroup ? '群組' : '' }}</span>
                            <span v-if="!item.isGroup && item.rawItem.auto_record && item.rawItem.auto_record.enabled" class="sub-item-sync-icon" title="自動記帳啟用" style="font-size: 0.8rem;">🔄</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Card: 投資 -->
            <div class="group-wrapper" v-if="investments.length > 0">
              <div class="group-header-card" :class="{ 'expanded-header bg-invest': listExpanded.invest }" @click="toggleListExpand('invest')" style="cursor: pointer;">
                <div class="card-header-main-row">
                  <span class="group-title-text" :class="{ 'text-dark': !listExpanded.invest, 'text-white': listExpanded.invest }">投資</span>
                  <div style="display: flex; flex-direction: column; align-items: flex-end;">
                    <span class="group-value-text" :class="{ 'text-dark': !listExpanded.invest, 'text-white': listExpanded.invest }">{{ isHidden ? '••••••' : formatCurrency(Math.round(totalInvestments)).replace('$', '') }}</span>
                    <!-- ROI badge for the entire portfolio -->
                    <span style="font-size: 0.78rem; font-weight: 700; margin-top: 4px;" :style="listExpanded.invest ? {
                      color: '#ffffff',
                      background: 'rgba(255, 255, 255, 0.2)',
                      padding: '2px 8px',
                      borderRadius: '8px',
                      display: 'inline-block'
                    } : {
                      color: totalInvestmentPnL >= 0 ? '#2ebd59' : '#ff453a'
                    }">
                      {{ totalInvestmentPnL >= 0 ? '+' : '' }}{{ isHidden ? '••••' : totalInvestmentPnL.toLocaleString('zh-TW', { minimumFractionDigits: 0, maximumFractionDigits: 0 }) }} ({{ totalInvestmentPnLPct >= 0 ? '+' : '' }}{{ totalInvestmentPnLPct.toFixed(2) }}%)
                    </span>
                  </div>
                </div>
                <div class="card-header-sub-row" v-if="!listExpanded.invest">
                  <div class="card-subtitle-col">
                    <span class="group-desc-subtitle">{{ investSubtitle }}</span>
                    <div class="three-dots-handle">
                      <span class="dot"></span>
                      <span class="dot"></span>
                      <span class="dot"></span>
                    </div>
                  </div>
                  <span class="group-update-date">{{ getLastUpdatedText('invest') }}</span>
                </div>
              </div>
              
              <div class="collapsible-wrapper" :class="{ expanded: listExpanded.invest }">
                <div class="collapsible-content">
                  <div class="group-body">
                    <div v-if="investListItems.length > 0" class="group-card-expanded-list" style="display: flex; flex-direction: column; gap: 4px; padding-bottom: 8px;">
                      <div v-for="item in investListItems" :key="item.isGroup ? 'g-' + item.name : 'i-' + item.symbol" class="sub-item-card" @click.stop="item.isGroup ? openCustomGroupDetail(item.name, 'invest') : openInvestmentDetail(item.symbol)" style="cursor: pointer;">
                        <!-- Circular Percentage Badge -->
                        <div class="sub-item-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; font-weight: 800;">
                          {{ Math.round(item.percentage) }}%
                        </div>
                        
                        <!-- Details (Left) -->
                        <div class="sub-item-info" style="display: flex; flex-direction: column; gap: 4px; justify-content: center; flex: 1; min-width: 0; text-align: left;">
                          <div class="sub-item-name" style="font-weight: 700; font-size: 1rem; color: var(--color-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{ item.name }}</div>
                          <div class="sub-item-desc" style="font-size: 0.8rem; color: var(--color-text-muted); display: flex; align-items: center; gap: 4px; flex-wrap: wrap;">
                            <template v-if="item.isGroup">
                              <span>{{ item.desc }}</span>
                            </template>
                            <template v-else>
                              <span>{{ isHidden ? '••••' : item.formattedQty }} 股</span>
                              <span style="opacity: 0.5;">·</span>
                              <span>{{ item.currency }} {{ isHidden ? '••••' : item.current_price }}</span>
                            </template>
                            <span v-if="item.price_updated_at" style="opacity: 0.5; margin-left: 2px; font-size: 0.7rem;">({{ formatDate(item.price_updated_at) }})</span>
                          </div>
                        </div>

                        <!-- Details (Right) -->
                        <div class="sub-item-right" style="display: flex; flex-direction: column; align-items: flex-end; gap: 4px; justify-content: center; flex-shrink: 0; text-align: right;">
                          <div class="sub-item-val" style="font-weight: 700; font-size: 0.95rem; color: var(--color-text); margin-bottom: 0;">
                            {{ isHidden ? '••••••' : formatCurrency(Math.round(item.valueTwd)).replace('$', '') }}
                          </div>
                          <!-- ROI Capsule Badge -->
                          <div v-if="item.pnlPct !== undefined" :style="{
                            color: item.pnl >= 0 ? '#2ebd59' : '#ff453a',
                            background: item.pnl >= 0 ? 'rgba(46, 189, 89, 0.1)' : 'rgba(255, 69, 58, 0.1)',
                            padding: '2px 8px',
                            borderRadius: '8px',
                            fontSize: '0.78rem',
                            fontWeight: '700'
                          }">
                            {{ item.pnl >= 0 ? '+' : '' }}{{ isHidden ? '••••' : Math.round(item.pnl).toLocaleString('zh-TW') }} ({{ item.pnl >= 0 ? '+' : '' }}{{ item.pnlPct.toFixed(2) }}%)
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Card: 固定資產 -->
            <div class="group-wrapper" v-if="filteredAccounts('fixed').length > 0">
              <div class="group-header-card" :class="{ 'expanded-header bg-fixed': listExpanded.fixed }" @click="toggleListExpand('fixed')" style="cursor: pointer;">
                <div class="card-header-main-row">
                  <span class="group-title-text" :class="{ 'text-dark': !listExpanded.fixed, 'text-white': listExpanded.fixed }">固定資產</span>
                  <span class="group-value-text" :class="{ 'text-dark': !listExpanded.fixed, 'text-white': listExpanded.fixed }">{{ isHidden ? '••••••' : formatCurrency(totalFixedAssets).replace('$', '') }}</span>
                </div>
                <div class="card-header-sub-row" v-if="!listExpanded.fixed">
                  <div class="card-subtitle-col">
                    <span class="group-desc-subtitle">{{ fixedSubtitle }}</span>
                    <div class="three-dots-handle">
                      <span class="dot"></span>
                      <span class="dot"></span>
                      <span class="dot"></span>
                    </div>
                  </div>
                  <span class="group-update-date">{{ getLastUpdatedText('fixed') }}</span>
                </div>
              </div>
              
              <div class="collapsible-wrapper" :class="{ expanded: listExpanded.fixed }">
                <div class="collapsible-content">
                  <div class="group-body">
                    <div v-if="getCategoryFlatList('fixed').length > 0" class="group-card-expanded-list" style="display: flex; flex-direction: column; gap: 4px; padding-bottom: 8px;">
                      <div v-for="item in getCategoryFlatList('fixed')" :key="item.isGroup ? 'g-' + item.name : 'a-' + item.rawItem.id" class="sub-item-card" @click.stop="item.isGroup ? openCustomGroupDetail(item.name, 'fixed') : editAccount(item.rawItem)" style="cursor: pointer;">
                        <!-- Circular Percentage Badge -->
                        <div class="sub-item-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; font-weight: 800;">
                          {{ Math.round(item.percentage) }}%
                        </div>
                        
                        <!-- Details -->
                        <div class="sub-item-info">
                          <template v-if="item.isGroup">
                            <div class="sub-item-name">{{ item.name }}</div>
                            <div class="sub-item-desc">{{ item.desc }}</div>
                          </template>
                          <template v-else>
                            <div style="display: flex; align-items: center; gap: 6px;">
                              <component :is="getTypeIconAndColor(item.rawItem.type).icon" :style="{ color: getTypeIconAndColor(item.rawItem.type).color }" size="16" weight="duotone" />
                              <span class="sub-item-name" style="font-weight: 600; color: var(--color-text);">{{ item.name }}</span>
                            </div>
                            <div class="sub-item-desc">{{ item.desc }}</div>
                          </template>
                        </div>

                        <!-- Value & Date -->
                        <div class="sub-item-right">
                          <div class="sub-item-val">
                            {{ isHidden ? '••••••' : formatCurrency(item.balance).replace('$', '') }}
                          </div>
                          <div class="sub-item-date" style="display: flex; align-items: center; gap: 4px; justify-content: flex-end;">
                            <span>{{ item.isGroup ? '群組' : '' }}</span>
                            <span v-if="!item.isGroup && item.rawItem.auto_record && item.rawItem.auto_record.enabled" class="sub-item-sync-icon" title="自動記帳啟用" style="font-size: 0.8rem;">🔄</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Card: 應收款 -->
            <div class="group-wrapper" v-if="filteredAccounts('receivable').length > 0">
              <div class="group-header-card" :class="{ 'expanded-header bg-receivable': listExpanded.receivable }" @click="toggleListExpand('receivable')" style="cursor: pointer;">
                <div class="card-header-main-row">
                  <span class="group-title-text" :class="{ 'text-dark': !listExpanded.receivable, 'text-white': listExpanded.receivable }">應收款</span>
                  <span class="group-value-text" :class="{ 'text-dark': !listExpanded.receivable, 'text-white': listExpanded.receivable }">{{ isHidden ? '••••••' : formatCurrency(totalReceivables).replace('$', '') }}</span>
                </div>
                <div class="card-header-sub-row" v-if="!listExpanded.receivable">
                  <div class="card-subtitle-col">
                    <span class="group-desc-subtitle">{{ receivableSubtitle }}</span>
                    <div class="three-dots-handle">
                      <span class="dot"></span>
                      <span class="dot"></span>
                      <span class="dot"></span>
                    </div>
                  </div>
                  <span class="group-update-date">{{ getLastUpdatedText('receivable') }}</span>
                </div>
              </div>
              
              <div class="collapsible-wrapper" :class="{ expanded: listExpanded.receivable }">
                <div class="collapsible-content">
                  <div class="group-body">
                    <div v-if="getCategoryFlatList('receivable').length > 0" class="group-card-expanded-list" style="display: flex; flex-direction: column; gap: 4px; padding-bottom: 8px;">
                      <div v-for="item in getCategoryFlatList('receivable')" :key="item.isGroup ? 'g-' + item.name : 'a-' + item.rawItem.id" class="sub-item-card" @click.stop="item.isGroup ? openCustomGroupDetail(item.name, 'receivable') : editAccount(item.rawItem)" style="cursor: pointer;">
                        <!-- Circular Percentage Badge -->
                        <div class="sub-item-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; font-weight: 800;">
                          {{ Math.round(item.percentage) }}%
                        </div>
                        
                        <!-- Details -->
                        <div class="sub-item-info">
                          <template v-if="item.isGroup">
                            <div class="sub-item-name">{{ item.name }}</div>
                            <div class="sub-item-desc">{{ item.desc }}</div>
                          </template>
                          <template v-else>
                            <div style="display: flex; align-items: center; gap: 6px;">
                              <component :is="getTypeIconAndColor(item.rawItem.type).icon" :style="{ color: getTypeIconAndColor(item.rawItem.type).color }" size="16" weight="duotone" />
                              <span class="sub-item-name" style="font-weight: 600; color: var(--color-text);">{{ item.name }}</span>
                            </div>
                            <div class="sub-item-desc">{{ item.desc }}</div>
                          </template>
                        </div>

                        <!-- Value & Date -->
                        <div class="sub-item-right">
                          <div class="sub-item-val">
                            {{ isHidden ? '••••••' : formatCurrency(item.balance).replace('$', '') }}
                          </div>
                          <div class="sub-item-date" style="display: flex; align-items: center; gap: 4px; justify-content: flex-end;">
                            <span>{{ item.isGroup ? '群組' : '' }}</span>
                            <span v-if="!item.isGroup && item.rawItem.auto_record && item.rawItem.auto_record.enabled" class="sub-item-sync-icon" title="自動記帳啟用" style="font-size: 0.8rem;">🔄</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Card: 負債項目 -->
            <div class="group-wrapper" v-if="filteredAccounts('liab').length > 0">
              <div class="group-header-card" :class="{ 'expanded-header bg-liab': listExpanded.liab }" @click="toggleListExpand('liab')" style="cursor: pointer;">
                <div class="card-header-main-row">
                  <span class="group-title-text" :class="{ 'text-dark': !listExpanded.liab, 'text-white': listExpanded.liab }">負債</span>
                  <div class="group-value-text liab-val-row" :class="{ 'text-dark': !listExpanded.liab, 'text-white': listExpanded.liab }">
                    <component :is="PhMinusCircle" size="20" weight="fill" :class="{ 'liab-minus-icon': !listExpanded.liab, 'text-white': listExpanded.liab }" />
                    <span>{{ isHidden ? '••••••' : formatCurrency(totalLiabilities).replace('$', '') }}</span>
                  </div>
                </div>
                <div class="card-header-sub-row" v-if="!listExpanded.liab">
                  <div class="card-subtitle-col">
                    <span class="group-desc-subtitle">{{ liabSubtitle }}</span>
                    <div class="three-dots-handle">
                      <span class="dot"></span>
                      <span class="dot"></span>
                      <span class="dot"></span>
                    </div>
                  </div>
                  <span class="group-update-date">{{ getLastUpdatedText('liab') }}</span>
                </div>
              </div>
              
              <div class="collapsible-wrapper" :class="{ expanded: listExpanded.liab }">
                <div class="collapsible-content">
                  <div class="group-body">
                    <div v-if="getCategoryFlatList('liab').length > 0" class="group-card-expanded-list" style="display: flex; flex-direction: column; gap: 4px; padding-bottom: 8px;">
                      <div v-for="item in getCategoryFlatList('liab')" :key="item.isGroup ? 'g-' + item.name : 'a-' + item.rawItem.id" class="sub-item-card" @click.stop="item.isGroup ? openCustomGroupDetail(item.name, 'liab') : editAccount(item.rawItem)" style="cursor: pointer;">
                        <!-- Circular Percentage Badge -->
                        <div class="sub-item-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; font-weight: 800;">
                          {{ Math.round(item.percentage) }}%
                        </div>
                        
                        <!-- Details -->
                        <div class="sub-item-info">
                          <template v-if="item.isGroup">
                            <div class="sub-item-name">{{ item.name }}</div>
                            <div class="sub-item-desc">{{ item.desc }}</div>
                          </template>
                          <template v-else>
                            <div style="display: flex; align-items: center; gap: 6px;">
                              <component :is="getTypeIconAndColor(item.rawItem.type).icon" :style="{ color: getTypeIconAndColor(item.rawItem.type).color }" size="16" weight="duotone" />
                              <span class="sub-item-name" style="font-weight: 600; color: var(--color-text);">{{ item.name }}</span>
                            </div>
                            <div class="sub-item-desc">{{ item.desc }}</div>
                          </template>
                        </div>

                        <!-- Value & Date -->
                        <div class="sub-item-right">
                          <div class="sub-item-val" style="color: var(--color-danger); display: flex; align-items: center; gap: 2px;">
                            <span>-</span>
                            <span>{{ isHidden ? '••••••' : formatCurrency(item.balance).replace('$', '') }}</span>
                          </div>
                          <div class="sub-item-date" style="display: flex; align-items: center; gap: 4px; justify-content: flex-end;">
                            <span>{{ item.isGroup ? '群組' : '' }}</span>
                            <span v-if="!item.isGroup && item.rawItem.auto_record && item.rawItem.auto_record.enabled" class="sub-item-sync-icon" title="自動記帳啟用" style="font-size: 0.8rem;">🔄</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Empty State -->
            <div v-if="accounts.length === 0 && investments.length === 0" class="empty-state">
               <div style="font-size: 2.2rem; margin-bottom: 0.5rem;">🏦</div>
               <div>尚無任何資產項目</div>
               <div style="font-size: 0.82rem; margin-top: 0.3rem; opacity: 0.6;">
                 請點擊右上角「+」按鈕開始加入資產、投資或負債。
               </div>
            </div>

          </div>
        </div>
      </template>
    </div>

    <!-- ── 2. 趨勢圖視圖 (Trend Tab) ────────────────────────────────── -->
    <div v-else-if="currentTab === 'trend'" key="trend" class="tab-view-content flex-grow-trend" style="background: var(--color-bg); height: 100vh; min-height: 100vh; padding: 0; color: var(--color-text); box-sizing: border-box; overflow: hidden; display: flex; flex-direction: column;">
      <!-- Fixed Header & Segment Selector Area -->
      <div style="flex-shrink: 0; padding: 0 16px; background: var(--color-bg);">
        <!-- Header -->
        <div class="modal-navbar" style="background: var(--color-bg); padding-top: 14px; padding-bottom: 14px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--color-card-border); margin-bottom: 0;">
          <!-- Empty Spacer to keep title centered -->
          <div style="width: 36px;"></div>
          <span class="nav-title" style="color: var(--color-text); font-size: 1.15rem; font-weight: 700;">趨勢圖</span>
          <!-- Close button X -->
          <button class="nav-back-circle" @click="currentTab = 'list'" title="關閉" style="background: rgba(0, 0, 0, 0.05); color: var(--color-text); width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; border: none; cursor: pointer; margin: 0;">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
          </button>
        </div>

        <!-- Segment Selector -->
        <div style="display: flex; background: rgba(0, 0, 0, 0.04); padding: 4px; border-radius: 20px; margin-top: 18px; margin-bottom: 20px; gap: 2px;">
          <button 
            @click="trendType = 'net_worth'"
            :style="{
              flex: 1,
              padding: '10px 0',
              borderRadius: '16px',
              border: 'none',
              fontSize: '0.85rem',
              fontWeight: '700',
              cursor: 'pointer',
              background: trendType === 'net_worth' ? '#ffffff' : 'transparent',
              color: trendType === 'net_worth' ? 'var(--color-text)' : 'var(--color-text-muted)',
              boxShadow: trendType === 'net_worth' ? '0 2px 4px rgba(0,0,0,0.05)' : 'none'
            }"
          >
            資產與分配走勢
          </button>
          <button 
            @click="trendType = 'roi'"
            :style="{
              flex: 1,
              padding: '10px 0',
              borderRadius: '16px',
              border: 'none',
              fontSize: '0.85rem',
              fontWeight: '700',
              cursor: 'pointer',
              background: trendType === 'roi' ? '#ffffff' : 'transparent',
              color: trendType === 'roi' ? 'var(--color-text)' : 'var(--color-text-muted)',
              boxShadow: trendType === 'roi' ? '0 2px 4px rgba(0,0,0,0.05)' : 'none'
            }"
          >
            投資報酬率
          </button>
        </div>
      </div>

      <!-- Scrollable Contents -->
      <div style="flex: 1; overflow-y: auto; padding: 0 16px; box-sizing: border-box; -webkit-overflow-scrolling: touch;">
        <!-- Date Range & Summary Info -->
        <div style="text-align: left; padding: 0 4px; margin-bottom: 24px;">
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 10px; flex-wrap: wrap; gap: 8px;">
            <div style="font-size: 0.85rem; color: var(--color-text-muted); font-weight: bold;">
              {{ trendDateRangeText }}
            </div>
            <!-- ROI / Return Rate Badge -->
            <div 
              v-if="trendPeriodROI !== 0"
              style="display: inline-flex; align-items: center; gap: 4px; padding: 4px 10px; border-radius: 12px; font-size: 0.78rem; font-weight: 700; cursor: default;"
              :style="{
                background: trendPeriodROI >= 0 ? 'rgba(46, 189, 89, 0.1)' : 'rgba(255, 69, 58, 0.1)',
                color: trendPeriodROI >= 0 ? '#2ebd59' : '#ff453a'
              }"
            >
              <span>{{ trendType === 'net_worth' ? '淨值增長率' : '投資報酬率' }}</span>
              <span>{{ trendPeriodROI >= 0 ? '+' : '' }}{{ trendPeriodROI.toFixed(2) }}%</span>
            </div>
          </div>
          <template v-if="trendType === 'net_worth' && netWorthSummaryText && liquidInvestSummaryText">
            <div style="display: flex; flex-direction: column; gap: 12px; text-align: left; width: 100%;">
              <!-- 3-Column Summary Panel -->
              <div style="
                display: grid; 
                grid-template-columns: repeat(3, minmax(0, 1fr)); 
                gap: 12px; 
                width: 100%;
              ">
                <!-- Net Worth Column -->
                <div style="
                  background: var(--color-card-bg); 
                  border: 1px solid var(--color-card-border); 
                  border-radius: 12px; 
                  padding: 12px;
                  display: flex;
                  flex-direction: column;
                  justify-content: space-between;
                  box-shadow: 0 2px 6px rgba(0,0,0,0.01);
                ">
                  <div>
                    <div style="font-size: 0.72rem; font-weight: 800; color: var(--color-text-muted); margin-bottom: 6px; border-left: 2px solid var(--color-primary); padding-left: 6px;">總淨資產變動</div>
                    <div style="display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px;">
                      <span style="font-size: 0.95rem; font-weight: 900; color: var(--color-text); font-family: 'Outfit', sans-serif;">
                        {{ isHidden ? '••••••' : formatInvestNumber(Math.round(netWorthSummaryText.lastVal - netWorthSummaryText.startVal)) }} 元
                      </span>
                    </div>
                    <div :style="{ 
                      color: netWorthSummaryText.diff >= 0 ? 'var(--color-success)' : 'var(--color-danger)', 
                      fontSize: '0.75rem', 
                      fontWeight: '800',
                      marginTop: '2px'
                    }">
                      {{ netWorthSummaryText.pct }}
                    </div>
                  </div>
                  <div style="font-size: 0.62rem; color: var(--color-text-muted); margin-top: 8px; border-top: 1px dashed rgba(0,0,0,0.04); padding-top: 6px; display: flex; flex-direction: column; gap: 2px;">
                    <div style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">期初：{{ isHidden ? '••••••' : formatInvestNumber(Math.round(netWorthSummaryText.startVal)) }}</div>
                    <div style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">目前：{{ isHidden ? '••••••' : formatInvestNumber(Math.round(netWorthSummaryText.lastVal)) }}</div>
                  </div>
                </div>

                <!-- Liquid Assets Column -->
                <div style="
                  background: var(--color-card-bg); 
                  border: 1px solid var(--color-card-border); 
                  border-radius: 12px; 
                  padding: 12px;
                  display: flex;
                  flex-direction: column;
                  justify-content: space-between;
                  box-shadow: 0 2px 6px rgba(0,0,0,0.01);
                ">
                  <!-- Header -->
                  <div>
                    <div style="font-size: 0.72rem; font-weight: 800; color: var(--color-text-muted); margin-bottom: 6px; border-left: 2px solid #2ec173; padding-left: 6px;">流動資金變動</div>
                    <div style="display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px;">
                      <span style="font-size: 0.95rem; font-weight: 900; color: var(--color-text); font-family: 'Outfit', sans-serif;">
                        {{ isHidden ? '••••••' : formatInvestNumber(liquidInvestSummaryText.liqDiff) }} 元
                      </span>
                    </div>
                    <div :style="{ 
                      color: liquidInvestSummaryText.liqDiff >= 0 ? 'var(--color-success)' : 'var(--color-danger)', 
                      fontSize: '0.75rem', 
                      fontWeight: '800',
                      marginTop: '2px'
                    }">
                      {{ liquidInvestSummaryText.liqPct }}
                    </div>
                  </div>
                  <div style="font-size: 0.62rem; color: var(--color-text-muted); margin-top: 8px; border-top: 1px dashed rgba(0,0,0,0.04); padding-top: 6px; display: flex; flex-direction: column; gap: 2px;">
                    <div style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">期初：{{ isHidden ? '••••••' : formatInvestNumber(Math.round(liquidInvestSummaryText.startLiq)) }}</div>
                    <div style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">目前：{{ isHidden ? '••••••' : formatInvestNumber(Math.round(liquidInvestSummaryText.lastLiq)) }}</div>
                  </div>
                </div>

                <!-- Investment Column -->
                <div style="
                  background: var(--color-card-bg); 
                  border: 1px solid var(--color-card-border); 
                  border-radius: 12px; 
                  padding: 12px;
                  display: flex;
                  flex-direction: column;
                  justify-content: space-between;
                  box-shadow: 0 2px 6px rgba(0,0,0,0.01);
                ">
                  <div>
                    <div style="font-size: 0.72rem; font-weight: 800; color: var(--color-text-muted); margin-bottom: 6px; border-left: 2px solid #7839ec; padding-left: 6px;">投資市值變動</div>
                    <div style="display: flex; flex-wrap: wrap; align-items: baseline; gap: 4px;">
                      <span style="font-size: 0.95rem; font-weight: 900; color: var(--color-text); font-family: 'Outfit', sans-serif;">
                        {{ isHidden ? '••••••' : formatInvestNumber(liquidInvestSummaryText.invDiff) }} 元
                      </span>
                    </div>
                    <div :style="{ 
                      color: liquidInvestSummaryText.invDiff >= 0 ? 'var(--color-success)' : 'var(--color-danger)', 
                      fontSize: '0.75rem', 
                      fontWeight: '800',
                      marginTop: '2px'
                    }">
                      {{ liquidInvestSummaryText.invPct }}
                    </div>
                  </div>
                  <div style="font-size: 0.62rem; color: var(--color-text-muted); margin-top: 8px; border-top: 1px dashed rgba(0,0,0,0.04); padding-top: 6px; display: flex; flex-direction: column; gap: 2px;">
                    <div style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">期初：{{ isHidden ? '••••••' : formatInvestNumber(Math.round(liquidInvestSummaryText.startInv)) }}</div>
                    <div style="white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">目前：{{ isHidden ? '••••••' : formatInvestNumber(Math.round(liquidInvestSummaryText.lastInv)) }}</div>
                  </div>
                </div>
              </div>
            </div>
          </template>
          <template v-else>
            <!-- Premium horizontal scrollable chip row -->
            <div style="display: flex; gap: 8px; overflow-x: auto; padding: 2px 0 4px; -webkit-overflow-scrolling: touch; scrollbar-width: none; -ms-overflow-style: none;">
              <!-- 整體 chip — indigo gradient glass -->
              <div 
                @mouseenter="hoveredGroup = 'overall'"
                @mouseleave="hoveredGroup = null"
                style="
                  flex-shrink: 0;
                  display: flex;
                  align-items: center;
                  gap: 7px;
                  padding: 6px 14px 6px 10px;
                  border-radius: 24px;
                  backdrop-filter: blur(8px);
                  transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
                  cursor: pointer;
                "
                :style="{
                  background: hoveredGroup === 'overall' ? 'rgba(92, 103, 245, 0.08)' : 'transparent',
                  border: hoveredGroup === 'overall' ? '1px solid rgba(92, 103, 245, 0.4)' : '1px solid rgba(92, 103, 245, 0.18)',
                  boxShadow: hoveredGroup === 'overall' 
                    ? '0 6px 16px rgba(92, 103, 245, 0.18)' 
                    : 'none',
                  transform: hoveredGroup === 'overall' ? 'translateY(-2px)' : 'translateY(0)'
                }"
              >
                <span style="
                  display: inline-flex;
                  width: 8px; height: 8px;
                  border-radius: 50%;
                  background: #5c67f5;
                  box-shadow: 0 0 6px rgba(92, 103, 245, 0.4);
                  flex-shrink: 0;
                "></span>
                <span style="font-size: 0.78rem; font-weight: 700; color: var(--color-text); opacity: 0.85; white-space: nowrap; letter-spacing: 0.02em;">整體</span>
                <span style="width: 1px; height: 12px; background: rgba(92, 103, 245, 0.15); flex-shrink: 0;"></span>
                <span style="font-size: 0.92rem; font-weight: 800; white-space: nowrap; letter-spacing: -0.02em;"
                  :style="{ color: totalInvestmentPnL >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }">
                  {{ totalInvestmentPnL >= 0 ? '+' : '' }}{{ totalInvestmentPnLPct.toFixed(2) }}%
                </span>
              </div>

              <!-- Per-group chips -->
              <div
                v-for="(metrics, grp) in roiByGroup"
                :key="'chip-' + grp"
                @mouseenter="hoveredGroup = grp"
                @mouseleave="hoveredGroup = null"
                style="
                  flex-shrink: 0;
                  display: flex;
                  align-items: center;
                  gap: 7px;
                  padding: 6px 14px 6px 10px;
                  border-radius: 24px;
                  backdrop-filter: blur(8px);
                  transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
                  cursor: pointer;
                "
                :style="{
                  background: hoveredGroup === grp ? getGroupColor(grp) + '0c' : 'transparent',
                  border: hoveredGroup === grp 
                    ? '1px solid ' + getGroupColor(grp) + '55' 
                    : '1px solid ' + getGroupColor(grp) + '24',
                  boxShadow: hoveredGroup === grp 
                    ? '0 6px 16px ' + getGroupColor(grp) + '22' 
                    : 'none',
                  transform: hoveredGroup === grp ? 'translateY(-2px)' : 'translateY(0)'
                }"
              >
                <span
                  style="display: inline-flex; width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0;"
                  :style="{
                    background: getGroupColor(grp),
                    boxShadow: '0 0 6px ' + getGroupColor(grp) + '66'
                  }"
                ></span>
                <span style="font-size: 0.78rem; font-weight: 700; white-space: nowrap; max-width: 72px; overflow: hidden; text-overflow: ellipsis; letter-spacing: 0.02em; color: var(--color-text); opacity: 0.85;">{{ grp }}</span>
                <span style="width: 1px; height: 12px; flex-shrink: 0; background: rgba(148, 163, 184, 0.25);"></span>
                <span style="font-size: 0.92rem; font-weight: 800; white-space: nowrap; letter-spacing: -0.02em;"
                  :style="{ color: metrics.roi >= 0 ? 'var(--color-success)' : 'var(--color-danger)' }">
                  {{ metrics.roi >= 0 ? '+' : '' }}{{ metrics.roi.toFixed(2) }}%
                </span>
              </div>
            </div>
          </template>
        </div>

        <!-- Line Chart Container -->
        <template v-if="trendType === 'net_worth'">
          <!-- Dual Chart Panel -->
          <div style="
            background: var(--color-card-bg); 
            border: 1px solid var(--color-card-border); 
            border-radius: 16px; 
            padding: 16px; 
            margin-bottom: 24px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.01);
            display: flex;
            flex-direction: column;
            gap: 20px;
          ">
            <!-- Chart 1: Net Worth & Liabilities -->
            <div>
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
                <span style="font-size: 0.82rem; font-weight: 800; color: var(--color-text); border-left: 3px solid var(--color-primary); padding-left: 8px;">淨資產與負債走勢</span>
                <!-- Mini Legend -->
                <div style="display: flex; gap: 12px; font-size: 0.72rem; color: var(--color-text-muted);">
                  <div style="display: flex; align-items: center; gap: 4px;">
                    <span style="width: 8px; height: 8px; background: #5c67f5; border-radius: 50%;"></span>
                    淨資產
                  </div>
                  <div style="display: flex; align-items: center; gap: 4px;">
                    <span style="width: 8px; height: 8px; background: #a0a0a5; border-radius: 50%;"></span>
                    負債
                  </div>
                </div>
              </div>
              <div style="height: 200px; position: relative;">
                <Line :data="netWorthChartData" :options="netWorthChartOptions" />
              </div>
            </div>

            <!-- Dashed Divider -->
            <div style="border-top: 1px dashed var(--color-card-border); margin: 4px 0;"></div>

            <!-- Chart 2: Liquid Cash & Investments -->
            <div>
              <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
                <span style="font-size: 0.82rem; font-weight: 800; color: var(--color-text); border-left: 3px solid #2ec173; padding-left: 8px;">流動資金與投資走勢</span>
                <!-- Mini Legend -->
                <div style="display: flex; gap: 12px; font-size: 0.72rem; color: var(--color-text-muted);">
                  <div style="display: flex; align-items: center; gap: 4px;">
                    <span style="width: 8px; height: 8px; background: #2ec173; border-radius: 50%;"></span>
                    流動資金
                  </div>
                  <div style="display: flex; align-items: center; gap: 4px;">
                    <span style="width: 8px; height: 8px; background: #7839ec; border-radius: 50%;"></span>
                    投資
                  </div>
                </div>
              </div>
              <div style="height: 200px; position: relative;">
                <Line :data="liquidInvestChartData" :options="liquidInvestChartOptions" />
              </div>
            </div>
          </div>
        </template>

        <!-- ROI Mode: Real Historical Chart -->
        <template v-else>
          <!-- Loading -->
          <div v-if="isFetchingRoiHistory && !roiHistoryChartData" style="height: 220px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.06); border-radius: 16px; margin-bottom: 32px;">
            <div class="loading-spinner" style="width: 22px; height: 22px; border-width: 3px;"></div>
            <span style="font-size: 0.8rem; color: var(--color-text-muted);">正在從 Yahoo Finance 取得歷史資料…</span>
          </div>
          <!-- Error -->
          <div v-else-if="roiHistoryError && !roiHistoryChartData" style="padding: 18px; background: rgba(255,69,58,0.07); border: 1px solid rgba(255,69,58,0.2); border-radius: 14px; font-size: 0.82rem; color: #ff6b61; text-align: center; margin-bottom: 32px;">
            ⚠️ {{ roiHistoryError }}
            <button @click="investmentPriceHistory = {}; fetchAllRoiHistory()" style="display: block; margin: 10px auto 0; font-size: 0.78rem; padding: 5px 14px; background: rgba(255,255,255,0.1); border: 1px solid rgba(255,255,255,0.15); color: var(--color-text); border-radius: 8px; cursor: pointer;">重試</button>
          </div>
          <!-- Real ROI Chart -->
          <div v-else-if="roiHistoryChartData" style="height: 260px; position: relative; margin-bottom: 24px;">
            <Line :data="roiHistoryChartData" :options="roiHistoryChartOptions" />
          </div>
          <!-- No data yet -->
          <div v-else style="height: 160px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px; background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.07); border-radius: 16px; margin-bottom: 32px;">
            <span style="font-size: 1.5rem;">📊</span>
            <span style="font-size: 0.82rem; color: var(--color-text-muted);">點擊右上角「更新」載入歷史報酬率走勢</span>
            <button @click="fetchAllRoiHistory()" style="font-size: 0.78rem; padding: 6px 16px; background: rgba(120,57,236,0.2); border: 1px solid rgba(120,57,236,0.4); color: #a87af5; border-radius: 8px; cursor: pointer; margin-top: 4px;">立即載入</button>
          </div>
        </template>

        <!-- Bottom Section Sub-Tabs (Clean Text Links with Underline style) -->
        <div v-if="trendType !== 'roi'" style="display: flex; gap: 24px; border-bottom: 1px solid var(--color-card-border); margin-top: 8px; margin-bottom: 20px; padding: 0 4px;">
          <button 
            @click="trendSubTab = 'details'"
            :style="{
              background: 'transparent',
              border: 'none',
              padding: '10px 0',
              fontSize: '0.85rem',
              fontWeight: '700',
              cursor: 'pointer',
              color: trendSubTab === 'details' ? 'var(--color-primary)' : 'var(--color-text-muted)',
              borderBottom: trendSubTab === 'details' ? '2px solid var(--color-primary)' : '2px solid transparent',
              transition: 'all 0.2s ease',
              marginBottom: '-1px',
              boxShadow: 'none',
              minHeight: 'unset',
              height: 'auto',
              outline: 'none',
              borderRadius: '0'
            }"
          >
            當日變動明細
          </button>
          <button 
            @click="trendSubTab = 'flow'"
            :style="{
              background: 'transparent',
              border: 'none',
              padding: '10px 0',
              fontSize: '0.85rem',
              fontWeight: '700',
              cursor: 'pointer',
              color: trendSubTab === 'flow' ? 'var(--color-primary)' : 'var(--color-text-muted)',
              borderBottom: trendSubTab === 'flow' ? '2px solid var(--color-primary)' : '2px solid transparent',
              transition: 'all 0.2s ease',
              marginBottom: '-1px',
              boxShadow: 'none',
              minHeight: 'unset',
              height: 'auto',
              outline: 'none',
              borderRadius: '0'
            }"
          >
            期間資金流向分析
          </button>
        </div>

        <!-- Interactive Node Details (Premium Clean Style) -->
        <div v-if="trendSubTab === 'details' && selectedHistoryDetails && trendType !== 'roi'" 
             style="
               background: var(--color-card-bg);
               border: 1px solid var(--color-card-border);
               border-radius: 16px;
               padding: 20px;
               margin-bottom: 24px;
               text-align: left;
               box-shadow: 0 4px 12px rgba(0, 0, 0, 0.01);
               transition: all 0.3s ease;
             "
        >
          <!-- Header Row -->
          <div style="display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 18px; border-bottom: 1px solid var(--color-card-border); padding-bottom: 12px; flex-wrap: wrap; gap: 8px;">
            <span style="font-size: 0.95rem; font-weight: 800; color: var(--color-text); letter-spacing: 0.3px;">{{ selectedHistoryDetails.date }} 淨值變動明細</span>
            <span style="font-size: 0.72rem; color: var(--color-text-muted); font-weight: 500;">點擊圖表節點切換</span>
          </div>
          
          <!-- Net Worth Info Row -->
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px; background: rgba(0, 0, 0, 0.015); padding: 12px 16px; border-radius: 12px; border: 1px solid var(--color-card-border); flex-wrap: wrap; gap: 12px;">
            <div>
              <div style="font-size: 0.72rem; color: var(--color-text-muted); font-weight: 800; margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.5px;">當日淨資產</div>
              <div style="font-size: 1.25rem; font-weight: 900; color: var(--color-text); font-family: 'Outfit', sans-serif;">
                {{ isHidden ? '••••••' : formatInvestNumber(selectedHistoryDetails.netWorth) }} <span style="font-size: 0.82rem; font-weight: 700; color: var(--color-text-muted);">元</span>
              </div>
            </div>
            <div v-if="selectedHistoryDetails.diff !== 0" style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 0.72rem; color: var(--color-text-muted); font-weight: 600;">較前一天</span>
              <span :style="{ 
                color: selectedHistoryDetails.diff >= 0 ? 'var(--color-success)' : 'var(--color-danger)', 
                fontSize: '0.82rem', 
                fontWeight: '800',
                background: selectedHistoryDetails.diff >= 0 ? 'rgba(46, 189, 89, 0.08)' : 'rgba(255, 69, 58, 0.08)',
                padding: '4px 10px',
                borderRadius: '8px',
                display: 'inline-block',
                fontFamily: 'Outfit, sans-serif'
              }">
                {{ selectedHistoryDetails.diff >= 0 ? '+' : '-' }}{{ formatInvestNumber(Math.abs(selectedHistoryDetails.diff)) }} 元
              </span>
            </div>
            <div v-else style="font-size: 0.78rem; color: var(--color-text-muted); font-weight: 700; background: rgba(0, 0, 0, 0.04); padding: 4px 10px; border-radius: 8px;">
              無變動
            </div>
          </div>

          <!-- Changes List (Grouped by Asset Category) -->
          <div v-if="selectedHistoryDetails.hasChanges" style="display: flex; flex-direction: column; gap: 16px; width: 100%;">
            
            <!-- Group 1: 流動資金帳戶 -->
            <div v-if="selectedHistoryDetails.liquidChanges.length > 0" style="display: flex; flex-direction: column; gap: 4px;">
              <div style="font-size: 0.72rem; font-weight: 800; color: var(--color-text-muted); border-left: 2px solid var(--color-primary); padding-left: 8px; margin-bottom: 6px; letter-spacing: 0.5px; text-transform: uppercase;">
                流動資金帳戶
              </div>
              
              <div v-for="chg in selectedHistoryDetails.liquidChanges" :key="chg.name" 
                   style="
                     display: flex; 
                     justify-content: space-between; 
                     align-items: center; 
                     padding: 8px 6px; 
                     border-radius: 8px;
                     transition: all 0.2s ease;
                   "
                   onmouseover="this.style.background='rgba(0, 0, 0, 0.02)'"
                   onmouseout="this.style.background='transparent'"
              >
                <div style="display: flex; flex-direction: column; align-items: flex-start; text-align: left; min-width: 0; flex: 1; padding-right: 12px;">
                  <span style="color: var(--color-text); font-size: 0.82rem; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%;">{{ chg.name }}</span>
                  <span v-if="chg.currency !== 'TWD'" style="font-size: 0.68rem; color: var(--color-text-muted); margin-top: 2px; font-weight: 600; background: rgba(0, 0, 0, 0.04); padding: 1px 5px; border-radius: 4px; align-self: flex-start;">
                    原幣：{{ chg.diff >= 0 ? '+' : '-' }}{{ chg.currency }} {{ formatInvestNumber(Math.abs(chg.diff)) }}
                  </span>
                </div>
                <span :style="{ 
                  fontWeight: '800', 
                  fontSize: '0.85rem',
                  color: chg.diffTwd >= 0 ? 'var(--color-success)' : 'var(--color-danger)',
                  fontFamily: 'Outfit, sans-serif',
                  flexShrink: 0
                }">
                  {{ chg.diffTwd >= 0 ? '+' : '-' }}{{ formatInvestNumber(Math.abs(chg.diffTwd)) }} 元
                </span>
              </div>
            </div>

            <!-- Group 2: 投資資產估值 -->
            <div v-if="selectedHistoryDetails.investChanges.length > 0" style="display: flex; flex-direction: column; gap: 4px;">
              <div style="font-size: 0.72rem; font-weight: 800; color: var(--color-text-muted); border-left: 2px solid #a855f7; padding-left: 8px; margin-bottom: 6px; letter-spacing: 0.5px; text-transform: uppercase;">
                投資資產估值
              </div>
              
              <div v-for="chg in selectedHistoryDetails.investChanges" :key="chg.name" 
                   style="
                     display: flex; 
                     justify-content: space-between; 
                     align-items: center; 
                     padding: 8px 6px; 
                     border-radius: 8px;
                     transition: all 0.2s ease;
                   "
                   onmouseover="this.style.background='rgba(0, 0, 0, 0.02)'"
                   onmouseout="this.style.background='transparent'"
              >
                <div style="display: flex; flex-direction: column; align-items: flex-start; text-align: left; min-width: 0; flex: 1; padding-right: 12px;">
                  <span style="color: var(--color-text); font-size: 0.82rem; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%;">{{ chg.name }}</span>
                  <span v-if="chg.currency !== 'TWD'" style="font-size: 0.68rem; color: var(--color-text-muted); margin-top: 2px; font-weight: 600; background: rgba(0, 0, 0, 0.04); padding: 1px 5px; border-radius: 4px; align-self: flex-start;">
                    原幣：{{ chg.diff >= 0 ? '+' : '-' }}{{ chg.currency }} {{ formatInvestNumber(Math.abs(chg.diff)) }}
                  </span>
                </div>
                <span :style="{ 
                  fontWeight: '800', 
                  fontSize: '0.85rem',
                  color: chg.diffTwd >= 0 ? 'var(--color-success)' : 'var(--color-danger)',
                  fontFamily: 'Outfit, sans-serif',
                  flexShrink: 0
                }">
                  {{ chg.diffTwd >= 0 ? '+' : '-' }}{{ formatInvestNumber(Math.abs(chg.diffTwd)) }} 元
                </span>
              </div>
            </div>

            <!-- Group 3: 負債項目變動 -->
            <div v-if="selectedHistoryDetails.liabChanges.length > 0" style="display: flex; flex-direction: column; gap: 4px;">
              <div style="font-size: 0.72rem; font-weight: 800; color: var(--color-text-muted); border-left: 2px solid #f97316; padding-left: 8px; margin-bottom: 6px; letter-spacing: 0.5px; text-transform: uppercase;">
                負債項目變動
              </div>
              
              <div v-for="chg in selectedHistoryDetails.liabChanges" :key="chg.name" 
                   style="
                     display: flex; 
                     justify-content: space-between; 
                     align-items: center; 
                     padding: 8px 6px; 
                     border-radius: 8px;
                     transition: all 0.2s ease;
                   "
                   onmouseover="this.style.background='rgba(0, 0, 0, 0.02)'"
                   onmouseout="this.style.background='transparent'"
              >
                <div style="display: flex; flex-direction: column; align-items: flex-start; text-align: left; min-width: 0; flex: 1; padding-right: 12px;">
                  <span style="color: var(--color-text); font-size: 0.82rem; font-weight: 700; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%;">{{ chg.name }}</span>
                  <span v-if="chg.currency !== 'TWD'" style="font-size: 0.68rem; color: var(--color-text-muted); margin-top: 2px; font-weight: 600; background: rgba(0, 0, 0, 0.04); padding: 1px 5px; border-radius: 4px; align-self: flex-start;">
                    原幣：{{ chg.diff >= 0 ? '+' : '-' }}{{ chg.currency }} {{ formatInvestNumber(Math.abs(chg.diff)) }}
                  </span>
                </div>
                <span :style="{ 
                  fontWeight: '800', 
                  fontSize: '0.85rem',
                  color: chg.diffTwd >= 0 ? 'var(--color-success)' : 'var(--color-danger)',
                  fontFamily: 'Outfit, sans-serif',
                  flexShrink: 0
                }">
                  {{ chg.diffTwd >= 0 ? '+' : '-' }}{{ formatInvestNumber(Math.abs(chg.diffTwd)) }} 元
                </span>
              </div>
            </div>

          </div>
          <div v-else style="font-size: 0.8rem; color: var(--color-text-muted); text-align: center; padding: 24px 0; background: rgba(0,0,0,0.01); border-radius: 12px; border: 1px dashed var(--color-card-border);">
            當天各帳目金額無明顯變動。
          </div>

          <!-- Daily Transactions list -->
          <div v-if="selectedHistoryDetails.transactions.length > 0" 
               style="
                 margin-top: 20px; 
                 padding-top: 16px; 
                 border-top: 1px dashed var(--color-card-border); 
                 display: flex; 
                 flex-direction: column; 
                 gap: 8px;
               "
          >
            <div style="font-size: 0.72rem; font-weight: 800; color: var(--color-text-muted); letter-spacing: 0.5px; border-left: 2px solid var(--color-primary); padding-left: 8px; margin-bottom: 6px; text-transform: uppercase;">當日交易事件</div>
            <div v-for="(tx, idx) in selectedHistoryDetails.transactions" :key="idx" 
                 style="
                   display: flex; 
                   align-items: center; 
                   justify-content: space-between;
                   font-size: 0.8rem; 
                   color: var(--color-text); 
                   font-weight: 600;
                   background: rgba(0, 0, 0, 0.015);
                   padding: 8px 12px;
                   border-radius: 8px;
                   border: 1px solid var(--color-card-border);
                 "
            >
              <div style="display: flex; align-items: center; gap: 8px;">
                <span :style="{
                  display: 'inline-block',
                  padding: '2px 6px',
                  borderRadius: '4px',
                  fontSize: '0.68rem',
                  fontWeight: '800',
                  color: tx.type === 'buy' ? 'var(--color-success)' : 'var(--color-danger)',
                  background: tx.type === 'buy' ? 'rgba(46, 189, 89, 0.08)' : 'rgba(255, 69, 58, 0.08)'
                }">
                  {{ tx.type === 'buy' ? '買入' : '賣出' }}
                </span>
                <span style="font-weight: 700;">{{ tx.symbol }}</span>
                <span style="color: var(--color-text-muted); font-size: 0.75rem;">{{ tx.quantity }} 股</span>
              </div>
              <span style="font-family: 'Outfit', sans-serif; font-size: 0.8rem; color: var(--color-text-muted);">
                價格: {{ tx.currency }} {{ tx.price || tx.buy_price }}
              </span>
            </div>
          </div>
        </div>

        <!-- Smart Money Flow Analysis Card (Neutral Theme Style, No Icons) -->
        <div 
          v-if="trendSubTab === 'flow' && trendType === 'net_worth' && moneyFlowAnalysis"
          style="
            background: var(--color-card-bg);
            border: 1px solid var(--color-card-border);
            border-radius: 16px;
            padding: 20px;
            margin-bottom: 24px;
            text-align: left;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.01);
          "
        >
          <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; border-bottom: 1px solid var(--color-card-border); padding-bottom: 12px;">
            <span style="font-size: 0.9rem; font-weight: 800; color: var(--color-text); letter-spacing: 0.3px;">{{ moneyFlowAnalysis.title }}</span>
            <button 
              @click="showFlowAnalysisModal = true"
              style="
                background: rgba(0, 0, 0, 0.03); 
                border: 1px solid var(--color-card-border); 
                border-radius: 8px; 
                padding: 6px 12px; 
                color: var(--color-text); 
                cursor: pointer; 
                font-size: 0.78rem; 
                font-weight: 700; 
                transition: all 0.2s; 
                outline: none;
                box-shadow: none;
                min-height: unset;
                height: auto;
              "
              onmouseover="this.style.background='rgba(0,0,0,0.06)'"
              onmouseout="this.style.background='rgba(0,0,0,0.03)'"
            >
              明細
            </button>
          </div>
          <div style="display: flex; flex-direction: column; gap: 10px;">
            <p style="font-size: 0.82rem; line-height: 1.6; color: var(--color-text-muted); margin: 0; font-weight: 500;">
              {{ moneyFlowAnalysis.summary }}
            </p>
            <div 
              v-if="moneyFlowAnalysis.tradeProfitText" 
              style="
                display: flex; 
                align-items: center; 
                gap: 8px; 
                font-size: 0.78rem; 
                font-weight: 700; 
                padding: 6px 12px; 
                border-radius: 8px; 
                align-self: flex-start;
              "
              :style="{
                background: moneyFlowAnalysis.tradeProfitText.includes('獲利') ? 'rgba(46, 189, 89, 0.08)' : 'rgba(255, 69, 58, 0.08)',
                color: moneyFlowAnalysis.tradeProfitText.includes('獲利') ? 'var(--color-success)' : 'var(--color-danger)',
                border: moneyFlowAnalysis.tradeProfitText.includes('獲利') ? '1px solid rgba(46, 189, 89, 0.12)' : '1px solid rgba(255, 69, 58, 0.12)'
              }"
            >
              <span>{{ moneyFlowAnalysis.tradeProfitText.replace('（', '').replace('）', '') }}</span>
            </div>
          </div>
        </div>

        <!-- Custom Date Picker Row -->
        <div v-if="timeFilter === 'ALL'" style="display: flex; align-items: center; margin-bottom: 20px; padding: 0 4px; width: 100%; box-sizing: border-box;">
          <div style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 4px; text-align: left; margin-right: 8px;">
            <span style="font-size: 0.75rem; color: var(--color-text-muted); font-weight: bold;">開始日期</span>
            <input type="date" v-model="customStartDate" class="reset-input" style="background: #f1f5f9 !important; border: 1px solid rgba(0,0,0,0.08) !important; color: var(--color-text) !important; padding: 8px 12px !important; border-radius: 12px !important; font-size: 0.85rem !important; width: 100% !important; box-sizing: border-box !important; outline: none; margin: 0 !important; height: auto !important; min-height: 38px !important; line-height: normal !important; -webkit-appearance: none !important;" />
          </div>
          <div style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 4px; text-align: left; margin-left: 8px;">
            <span style="font-size: 0.75rem; color: var(--color-text-muted); font-weight: bold;">結束日期</span>
            <input type="date" v-model="customEndDate" class="reset-input" style="background: #f1f5f9 !important; border: 1px solid rgba(0,0,0,0.08) !important; color: var(--color-text) !important; padding: 8px 12px !important; border-radius: 12px !important; font-size: 0.85rem !important; width: 100% !important; box-sizing: border-box !important; outline: none; margin: 0 !important; height: auto !important; min-height: 38px !important; line-height: normal !important; -webkit-appearance: none !important;" />
          </div>
        </div>

        <!-- Capsule Time Filter Selector -->
        <div style="display: flex; background: rgba(0, 0, 0, 0.04); padding: 4px; border-radius: 25px; gap: 4px; margin-bottom: 20px;">
          <button 
            v-for="time in [
              { label: '30天', value: '30D' },
              { label: '6個月', value: '6M' },
              { label: '1年', value: '1Y' },
              { label: '年初至今', value: 'YTD' },
              { label: '自訂', value: 'ALL' }
            ]"
            :key="time.value"
            @click="timeFilter = time.value"
            :style="{
              flex: 1,
              padding: '10px 0',
              borderRadius: '20px',
              border: 'none',
              fontSize: '0.82rem',
              fontWeight: '700',
              cursor: 'pointer',
              background: timeFilter === time.value ? '#ffffff' : 'transparent',
              color: timeFilter === time.value ? 'var(--color-text)' : 'var(--color-text-muted)',
              boxShadow: timeFilter === time.value ? '0 2px 4px rgba(0,0,0,0.05)' : 'none'
            }"
          >
            {{ time.label }}
          </button>
        </div>

        <!-- ── 投資報酬率快速更新按鈕（僅 roi 模式顯示）──────────── -->
        <div v-if="trendType === 'roi' && groupedInvestments.length > 0" style="margin-bottom: 20px; display: flex; justify-content: flex-end;">
          <button
            @click="investmentPriceHistory = {}; fetchAllRoiHistory()"
            :disabled="isFetchingRoiHistory"
            style="display: flex; align-items: center; gap: 5px; background: rgba(255,255,255,0.07); border: 1px solid rgba(255,255,255,0.12); color: var(--color-text-muted); padding: 6px 14px; border-radius: 10px; font-size: 0.75rem; font-weight: 600; cursor: pointer;"
          >
            <svg :class="{ spin: isFetchingRoiHistory }" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
              <path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/>
            </svg>
            {{ isFetchingRoiHistory ? '載入中…' : '更新歷史資料' }}
          </button>
        </div>




        <!-- Bottom spacer to prevent overlap with floating BottomNav -->
        <div style="height: 110px; flex-shrink: 0;"></div>
      </div>
    </div>

    <!-- ── 3. 資料管理視圖 (Settings Tab) ────────────────────────────── -->
    <div v-else-if="currentTab === 'settings'" key="settings" class="tab-view-content" style="gap: 1rem;">
      <div class="settings-header-row">
        <h3>管理所有原始帳目</h3>
      </div>

      <!-- Accounts Table List -->
      <div class="settings-section card">
        <h4 class="section-title">🏦 流動、固定、應收與負債</h4>
        <div class="settings-table-list" v-if="accounts.length > 0">
          <div v-for="acc in accounts" :key="acc.id" class="settings-table-item" @click="editAccount(acc)">
            <div class="item-meta">
              <span class="item-name">{{ acc.name }}</span>
              <span class="item-type-badge">{{ translateTypeSettings(acc.type) }}</span>
            </div>
            <div class="item-right-wrap">
              <span class="item-value">{{ isHidden ? '••••••' : formatCurrency(acc.balance) }}</span>
              <button class="delete-btn" @click.stop="deleteAccount(acc.id)" title="刪除">
                <PhTrash size="16" />
              </button>
            </div>
          </div>
        </div>
        <div v-else class="settings-empty">目前尚無帳戶資料</div>
      </div>

      <!-- Investments Table List -->
      <div class="settings-section card" style="margin-top: 1rem;">
        <h4 class="section-title">📈 證券與投資部位</h4>
        <div class="settings-table-list" v-if="investments.length > 0">
          <div v-for="inv in investments" :key="inv.id" class="settings-table-item" @click="editInvestment(inv)">
            <div class="item-meta">
              <span class="item-name">{{ inv.symbol }} ({{ inv.name }})</span>
              <span class="item-type-badge">{{ translateTypeSettings(inv.asset_class) }} · {{ isHidden ? '••••••' : inv.quantity }} 單位 @ {{ inv.currency }} {{ isHidden ? '••••••' : inv.buy_price }}</span>
            </div>
            <div class="item-right-wrap">
              <span class="item-value">{{ isHidden ? '••••••' : formatCurrency(inv.quantity * inv.current_price) }}</span>
              <button class="delete-btn" @click.stop="deleteInvestment(inv.id)" title="刪除">
                <PhTrash size="16" />
              </button>
            </div>
          </div>
        </div>
        <div v-else class="settings-empty">目前尚無投資資料</div>
      </div>

      <!-- Historical Net Worth Snapshots Management -->
      <div class="settings-section card" style="margin-top: 1rem;">
        <h4 class="section-title">📅 歷史淨值快照管理</h4>
        <div class="settings-table-list" v-if="historyRecords.length > 0">
          <div v-for="rec in [...historyRecords].reverse().slice(0, 15)" :key="rec.date" class="settings-table-item" style="cursor: default;">
            <div class="item-meta">
              <span class="item-name" style="font-weight: bold;">{{ rec.date }}</span>
              <span class="item-type-badge">快照金額：{{ isHidden ? '••••••' : formatCurrency(rec.amount) }} 元</span>
            </div>
            <div class="item-right-wrap" style="gap: 8px;">
              <button class="icon-text-btn" style="padding: 4px 8px; border-radius: 8px; font-size: 0.72rem; border: 1px solid rgba(0,0,0,0.08); background: #f8fafc; cursor: pointer; box-shadow: none;" @click.stop="editSnapshotAmount(rec)" title="修改金額">
                ✏️ 修改
              </button>
              <button class="delete-btn" @click.stop="deleteSnapshot(rec.date)" title="刪除快照">
                <PhTrash size="16" />
              </button>
            </div>
          </div>
          <div v-if="historyRecords.length > 15" class="settings-empty" style="padding: 8px 0; font-size: 0.78rem; border-top: 1px solid rgba(0,0,0,0.03);">
            僅顯示最近 15 筆快照紀錄
          </div>
        </div>
        <div v-else class="settings-empty">目前尚無歷史快照紀錄</div>
      </div>

      <!-- Custom Account Groups Table List -->
      <div class="settings-section card" style="margin-top: 1rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.8rem;">
          <h4 class="section-title" style="margin: 0;">🏦 自訂帳戶群組管理</h4>
          <button class="icon-text-btn" @click="openCreateGroupModal('account')" style="padding: 4px 10px; font-size: 0.8rem; background: var(--color-primary); color: white; border-radius: 8px; display: flex; align-items: center; gap: 4px; border: none; cursor: pointer;">
            <PhPlus size="14" />
            <span>新增群組</span>
          </button>
        </div>
        <div class="settings-table-list" v-if="customAccountGroupsList.length > 0">
          <div v-for="grp in customAccountGroupsList" :key="grp" class="settings-table-item" @click="manageGroup(grp, 'account')">
            <div class="item-meta">
              <span class="item-name">{{ grp }}</span>
              <span class="item-type-badge">{{ getGroupMemberCount(grp, 'account') }} 個項目</span>
            </div>
            <div class="item-right-wrap">
              <button class="delete-btn" @click.stop="deleteGroup(grp, 'account')" title="刪除">
                <PhTrash size="16" />
              </button>
            </div>
          </div>
        </div>
        <div v-else class="settings-empty">目前尚無自訂帳戶群組</div>
      </div>

      <!-- Custom Invest Groups Table List -->
      <div class="settings-section card" style="margin-top: 1rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.8rem;">
          <h4 class="section-title" style="margin: 0;">📈 自訂投資群組管理</h4>
          <button class="icon-text-btn" @click="openCreateGroupModal('invest')" style="padding: 4px 10px; font-size: 0.8rem; background: var(--color-primary); color: white; border-radius: 8px; display: flex; align-items: center; gap: 4px; border: none; cursor: pointer;">
            <PhPlus size="14" />
            <span>新增群組</span>
          </button>
        </div>
        <div class="settings-table-list" v-if="customInvestGroupsList.length > 0">
          <div v-for="grp in customInvestGroupsList" :key="grp" class="settings-table-item" @click="manageGroup(grp, 'invest')">
            <div class="item-meta">
              <span class="item-name">{{ grp }}</span>
              <span class="item-type-badge">{{ getGroupMemberCount(grp, 'invest') }} 個項目</span>
            </div>
            <div class="item-right-wrap">
              <button class="delete-btn" @click.stop="deleteGroup(grp, 'invest')" title="刪除">
                <PhTrash size="16" />
              </button>
            </div>
          </div>
        </div>
        <div v-else class="settings-empty">目前尚無自訂投資群組</div>
      </div>

      <!-- Advanced Settings / Data Reset -->
      <div class="settings-section card" style="margin-top: 1rem; border: 1px solid rgba(255, 69, 58, 0.2); background: rgba(255, 69, 58, 0.02);">
        <h4 class="section-title" style="color: var(--color-danger); margin-bottom: 0.5rem;">⚠️ 進階資料管理</h4>
        <p style="font-size: 0.8rem; color: var(--color-text-muted); margin-bottom: 1rem; line-height: 1.4;">
          如果您刪除了測試用的資產或投資，導致歷史走勢圖的基準點不正確，您可以使用此功能清空歷史走勢紀錄。系統將以您目前的資產狀態重新開始計算走勢。
        </p>
        <button 
          @click="clearNetWorthHistory" 
          style="width: 100%; padding: 12px; background: var(--color-danger); color: white; border: none; border-radius: 12px; font-weight: 700; font-size: 0.9rem; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 6px; box-shadow: 0 4px 12px rgba(255, 69, 58, 0.2); transition: all 0.2s;"
          onmouseover="this.style.opacity='0.9'"
          onmouseout="this.style.opacity='1'"
        >
          <PhTrash size="16" />
          <span>重置走勢圖歷史紀錄</span>
        </button>
      </div>



      <!-- Bottom spacer to prevent overlap with floating BottomNav -->
      <div style="height: 110px; flex-shrink: 0;"></div>
    </div>
    </Transition>

    <!-- ── 4. Unified Add Modal (Step 1: Accordion menu | Step 1.5: Provider list | Step 2: Form | Step 3: Auto-Record) ── -->
    <Transition name="modal-slide">
      <div v-if="showAddModal" class="modal-overlay" style="z-index: 2200;" @click.self="closeAddModal()">
        
        <Transition name="fade-tab" mode="out-in">
          <!-- Step 1: Accordion list matching Percento screenshot -->
          <div class="modal-content-full" v-if="addModalStep === 1" key="step1">
        <!-- Navbar matching native mobile app screenshot -->
        <div class="modal-navbar">
          <button class="nav-back-circle" @click="closeAddModal()" title="關閉">
            <PhCaretLeft size="20" weight="bold" />
          </button>
          <span class="nav-title">新增帳戶</span>
          <div class="nav-placeholder"></div>
        </div>

        <div class="cat-blocks-stack">
          
          <!-- Group 1: 流動資金 -->
          <div class="cat-group-wrapper">
            <button class="cat-block-btn block-liquid" @click="toggleAccordion('liquid')">
              流動資金
            </button>
            <transition name="accordion-slide">
              <div class="accordion-panel" v-if="expandedCategories.liquid">
                <button class="sub-type-item" @click="selectSubtype('liquid', 'Cash', '現金')">
                  <div class="sub-item-left">
                    <PhWallet class="sub-icon text-green" size="20" weight="duotone" />
                    <span>現金</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="openSubList('E-Wallet')">
                  <div class="sub-item-left">
                    <PhCloudArrowUp class="sub-icon text-green" size="20" weight="duotone" />
                    <span>電子錢包</span>
                  </div>
                  <PhCaretRight class="chevron-icon" size="16" weight="bold" />
                </button>
                <button class="sub-type-item" @click="selectSubtype('liquid', 'Bank', '銀行帳戶')">
                  <div class="sub-item-left">
                    <PhCreditCard class="sub-icon text-green" size="20" weight="duotone" />
                    <span>銀行帳戶</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="selectSubtype('liquid', 'OtherLiquid', '其他')">
                  <div class="sub-item-left">
                    <PhCards class="sub-icon text-green" size="20" weight="duotone" />
                    <span>其他</span>
                  </div>
                </button>
              </div>
            </transition>
          </div>

          <!-- Group 2: 投資 -->
          <div class="cat-group-wrapper">
            <button class="cat-block-btn block-invest" @click="toggleAccordion('invest')">
              投資
            </button>
            <transition name="accordion-slide">
              <div class="accordion-panel" v-if="expandedCategories.invest">
                <button class="sub-type-item" @click="selectSubtype('invest', 'Fund', '投資基金')">
                  <div class="sub-item-left">
                    <PhCurrencyCny class="sub-icon text-purple" size="20" weight="duotone" />
                    <span>投資基金</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="openSubList('Stock')">
                  <div class="sub-item-left">
                    <PhChartBar class="sub-icon text-purple" size="20" weight="duotone" />
                    <span>股票</span>
                  </div>
                  <PhCaretRight class="chevron-icon" size="16" weight="bold" />
                </button>
                <button class="sub-type-item" @click="selectSubtype('invest', 'Crypto', '加密貨幣')">
                  <div class="sub-item-left">
                    <PhCurrencyBtc class="sub-icon text-purple" size="20" weight="duotone" />
                    <span>加密貨幣</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="selectSubtype('invest', 'Metal', '貴金屬')">
                  <div class="sub-item-left">
                    <PhCube class="sub-icon text-purple" size="20" weight="duotone" />
                    <span>貴金屬</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="openSubList('OtherInvest')">
                  <div class="sub-item-left">
                    <PhLeaf class="sub-icon text-purple" size="20" weight="duotone" />
                    <span>其他投資</span>
                  </div>
                  <PhCaretRight class="chevron-icon" size="16" weight="bold" />
                </button>
              </div>
            </transition>
          </div>

          <!-- Group 3: 固定資產 -->
          <div class="cat-group-wrapper">
            <button class="cat-block-btn block-fixed" @click="toggleAccordion('fixed')">
              固定資產
            </button>
            <transition name="accordion-slide">
              <div class="accordion-panel" v-if="expandedCategories.fixed">
                <button class="sub-type-item" @click="selectSubtype('fixed', 'RealEstate', '房產')">
                  <div class="sub-item-left">
                    <PhBuildings class="sub-icon text-blue" size="20" weight="duotone" />
                    <span>房產</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="selectSubtype('fixed', 'Car', '汽車')">
                  <div class="sub-item-left">
                    <PhCar class="sub-icon text-blue" size="20" weight="duotone" />
                    <span>汽車</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="selectSubtype('fixed', 'OtherFixed', '其他固定資產')">
                  <div class="sub-item-left">
                    <PhLock class="sub-icon text-blue" size="20" weight="duotone" />
                    <span>其他固定資產</span>
                  </div>
                </button>
              </div>
            </transition>
          </div>

          <!-- Group 4: 應收款 -->
          <div class="cat-group-wrapper">
            <button class="cat-block-btn block-receivable" @click="toggleAccordion('receivable')">
              應收款
            </button>
            <transition name="accordion-slide">
              <div class="accordion-panel" v-if="expandedCategories.receivable">
                <button class="sub-type-item" @click="selectSubtype('receivable', 'Receivable', '應收款')">
                  <div class="sub-item-left">
                    <PhUsers class="sub-icon text-light-blue" size="20" weight="duotone" />
                    <span>應收款</span>
                  </div>
                </button>
              </div>
            </transition>
          </div>

          <!-- Group 5: 負債 -->
          <div class="cat-group-wrapper">
            <button class="cat-block-btn block-liab" @click="toggleAccordion('liab')">
              負債
            </button>
            <transition name="accordion-slide">
              <div class="accordion-panel" v-if="expandedCategories.liab">
                <button class="sub-type-item" @click="selectSubtype('liab', 'Credit Card', '信用卡')">
                  <div class="sub-item-left">
                    <PhCreditCard class="sub-icon text-gray-blue" size="20" weight="duotone" />
                    <span>信用卡</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="openSubList('Loan')">
                  <div class="sub-item-left">
                    <PhBank class="sub-icon text-gray-blue" size="20" weight="duotone" />
                    <span>貸款</span>
                  </div>
                  <PhCaretRight class="chevron-icon" size="16" weight="bold" />
                </button>
                <button class="sub-type-item" @click="selectSubtype('liab', 'Payable', '應付款')">
                  <div class="sub-item-left">
                    <PhCreditCard class="sub-icon text-gray-blue" size="20" weight="duotone" />
                    <span>應付款</span>
                  </div>
                </button>
                <button class="sub-type-item" @click="selectSubtype('liab', 'OtherLiab', '其他負債')">
                  <div class="sub-item-left">
                    <PhCreditCard class="sub-icon text-gray-blue" size="20" weight="duotone" />
                    <span>其他負債</span>
                  </div>
                </button>
              </div>
            </transition>
          </div>

        </div>
      </div>

      <!-- Step 1.5: Sub-Type specific options (E-Wallet, Stock, Loan, etc.) -->
      <div class="modal-content-full" v-else-if="addModalStep === 1.5" key="step1_5">
        <div class="modal-navbar">
          <button class="nav-back-circle" @click="addModalStep = 1" title="返回">
            <PhCaretLeft size="20" weight="bold" />
          </button>
          <span class="nav-title">{{ subListTitle }}</span>
          <div class="nav-placeholder"></div>
        </div>

        <div class="cat-blocks-stack" style="margin-top: 16px;">
          <button v-for="item in subListOptions" :key="item.label" class="sub-type-item" @click="selectProvider(item)">
            <div class="sub-item-left">
              <component :is="item.icon" class="sub-icon" :class="item.colorClass" size="20" weight="duotone" />
              <span>{{ item.label }}</span>
            </div>
          </button>
        </div>
      </div>

      <!-- Step 2: Specific Input Form with Back arrow button -->
      <div class="modal-content-full" v-else-if="addModalStep === 2" key="step2" :style="{ '--focused-color': getCategoryThemeColor(newAsset.category) }">
        <div class="modal-navbar">
          <button class="nav-back-circle" @click="isEditing ? closeAddModal() : (subListType ? addModalStep = 1.5 : addModalStep = 1)" title="返回">
            <PhCaretLeft size="20" weight="bold" />
          </button>
          <span class="nav-title">{{ newAsset.category === 'invest' ? '投資' : '帳戶' }}</span>
          <!-- Save checkmark in top right navbar -->
          <button class="nav-save-circle" @click="addAssetItem" :disabled="isSaving" title="儲存">
            <div v-if="isSaving" class="mini-spinner"></div>
            <PhCheck v-else size="20" weight="bold" />
          </button>
        </div>

        <div class="provider-type-row">
          <span class="row-label-gray">帳戶</span>
          <div class="provider-type-right">
            <template v-if="['Stock', 'Fund'].includes(newAsset.type)">
              <div class="region-badge-circle" :style="{ background: isTaiwanStock(newAsset.symbol) ? 'rgba(120,57,236,0.15)' : 'rgba(92,103,245,0.15)', color: isTaiwanStock(newAsset.symbol) ? '#7839ec' : '#5c67f5', border: isTaiwanStock(newAsset.symbol) ? '1px solid rgba(120,57,236,0.3)' : '1px solid rgba(92,103,245,0.3)', width: '24px', height: '24px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 'bold', fontSize: '0.65rem', marginRight: '6px' }">
                {{ isTaiwanStock(newAsset.symbol) ? 'TW' : 'US' }}
              </div>
              <span class="provider-type-text">{{ isTaiwanStock(newAsset.symbol) ? '台股' : '美股' }}</span>
            </template>
            <template v-else>
              <component :is="getTypeIconAndColor(newAsset.type).icon" class="sub-icon" :class="getTypeIconAndColor(newAsset.type).color" size="20" weight="duotone" />
              <span class="provider-type-text">{{ translateTypeSettings(newAsset.type) }}</span>
            </template>
          </div>
        </div>

        <div class="form-body">
          
          <!-- Case A: Stock, Crypto, Fund (Investment Lot fields) -->
          <template v-if="['Stock', 'Crypto', 'Fund'].includes(newAsset.type)">
            <div class="form-card-black">
              <!-- 股票代號 -->
              <div class="form-item-row">
                <div class="row-label-group" style="display: flex; flex-direction: row; align-items: center; gap: 4px;">
                  <span class="row-label">股票代號</span>
                  <PhInfo size="14" style="color: var(--color-text-muted); opacity: 0.8;" />
                </div>
                <div class="row-value-wrapper" style="display: flex; align-items: center; gap: 8px;">
                  <input v-model="newAsset.symbol" :placeholder="newAsset.type === 'Stock' ? 'TSLA 或 0050' : 'BTC'" class="input-flat-right text-right" style="text-transform: uppercase; font-weight: 700; width: 120px;" @blur="validateSymbol" />
                </div>
              </div>

              <!-- 驗證狀態列 -->
              <div v-if="verificationResult" style="margin: 8px 18px; padding: 12px 16px; border-radius: 12px; font-size: 0.82rem; transition: all 0.3s ease;"
                   :style="{
                     background: verificationResult.loading 
                       ? 'rgba(92, 103, 245, 0.06)' 
                       : (verificationResult.success ? 'rgba(46, 189, 89, 0.06)' : 'rgba(255, 69, 58, 0.06)'),
                     border: verificationResult.loading 
                       ? '1px solid rgba(92, 103, 245, 0.15)' 
                       : (verificationResult.success ? '1px solid rgba(46, 189, 89, 0.15)' : '1px solid rgba(255, 69, 58, 0.15)'),
                   }">
                <!-- Loading State -->
                <div v-if="verificationResult.loading" style="display: flex; align-items: center; gap: 8px; color: #5c67f5;">
                  <PhArrowClockwise size="16" class="spin" />
                  <span style="font-weight: 600;">正在向 Yahoo Finance 驗證並取得最新股價...</span>
                </div>
                <!-- Success State -->
                <div v-else-if="verificationResult.success" style="display: flex; align-items: center; gap: 6px; color: #1b8a5a; font-weight: 700;">
                  <PhCheckCircle size="16" weight="fill" style="color: #2ebd59; flex-shrink: 0;" />
                  <span>{{ verificationResult.symbol }} · 市價 TWD {{ (verificationResult.currency === 'USD' ? (verificationResult.price * usdTwdRate).toFixed(2) : verificationResult.price.toFixed(2)) }} ({{ verificationResult.currency }} {{ verificationResult.price }})</span>
                </div>
                <!-- Error State -->
                <div v-else style="display: flex; align-items: center; gap: 8px; color: #b91c1c; font-weight: 600;">
                  <PhInfo size="16" weight="fill" style="color: #ff453a;" />
                  <span>{{ verificationResult.msg }}</span>
                </div>
              </div>

              <!-- 股數 -->
              <div class="form-item-row" style="padding: 14px 18px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); display: flex; justify-content: space-between; align-items: center;">
                <span class="row-label">股數</span>
                <div class="row-value-wrapper" style="display: flex; align-items: center; gap: 8px;">
                  <input v-model.number="newAsset.quantity" type="number" step="0.0001" placeholder="0" class="input-flat-right text-right" style="font-weight: 700; font-size: 1.15rem; width: 120px;" />
                  <span class="currency-badge" style="background: rgba(255,255,255,0.08); padding: 4px 8px; border-radius: 6px; font-size: 0.75rem; font-weight: 700; color: var(--color-text-muted);">股</span>
                </div>
              </div>

              <!-- 買入單價 -->
              <div class="form-item-row" style="padding: 14px 18px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); display: flex; justify-content: space-between; align-items: center;">
                <span class="row-label">買入單價</span>
                <div class="row-value-wrapper" style="display: flex; align-items: center; gap: 8px;">
                  <input v-model.number="newAsset.buy_price" type="number" step="0.01" placeholder="0.00" class="input-flat-right text-right" style="font-weight: 700; font-size: 1.15rem; width: 120px;" />
                  <span class="currency-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; padding: 4px 8px; border-radius: 6px; font-size: 0.75rem; font-weight: 700;">
                    {{ isTaiwanStock(newAsset.symbol) ? 'TWD' : 'USD' }}
                  </span>
                </div>
              </div>

              <!-- 預估總成本 -->
              <div class="form-item-row" style="padding: 14px 18px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); display: flex; justify-content: space-between; align-items: center; background: rgba(255,255,255,0.01);">
                <span class="row-label" style="font-size: 0.85rem; color: var(--color-text-muted);">預估總成本</span>
                <span style="font-size: 1rem; font-weight: 700; color: var(--color-text-muted);">
                  {{ isTaiwanStock(newAsset.symbol) ? 'TWD' : 'USD' }} {{ formatInvestNumber(Number(newAsset.quantity || 0) * Number(newAsset.buy_price || 0)) }}
                </span>
              </div>

              <!-- 自定名稱 -->
              <div class="form-item-row">
                <span class="row-label">自定名稱</span>
                <input v-model="newAsset.name" placeholder="例: 元大台灣 50" class="input-flat-right text-right" />
              </div>



              <!-- 自訂群組 -->
              <div class="form-item-row" style="position: relative;">
                <span class="row-label">自訂群組</span>
                <div class="row-value-wrapper">
                  <span class="display-val" style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">
                    {{ newAsset.custom_group || '無群組' }}
                  </span>
                  <PhCaretRight size="16" class="caret-indicator" />
                </div>
                <select v-model="newAsset.custom_group" @change="handleCustomGroupChange('invest')" class="invisible-select">
                  <option value="">無群組</option>
                  <option v-for="grp in customInvestGroupsList" :key="grp" :value="grp">{{ grp }}</option>
                  <option value="__NEW__">+ 新增群組...</option>
                </select>
              </div>

              <!-- 計入圖表 -->
              <div class="form-item-row">
                <span class="row-label">計入圖表</span>
                <label class="toggle-switch">
                  <input type="checkbox" v-model="newAsset.include_in_chart" />
                  <span class="toggle-slider"></span>
                </label>
              </div>

              <!-- 備註 -->
              <div class="form-item-row">
                <span class="row-label">備註</span>
                <input v-model="newAsset.remarks" placeholder="輸入備註" class="input-flat-right text-right" />
              </div>

              <!-- 扣款帳戶 -->
              <div class="form-item-row" style="position: relative;" :style="{ borderBottom: newAsset.funding_account_id ? '1px solid rgba(255, 255, 255, 0.05)' : 'none' }">
                <span class="row-label">扣款帳戶</span>
                <div class="row-value-wrapper">
                  <span class="display-val" style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">
                    {{ accounts.find(a => a.id === newAsset.funding_account_id)?.name || '無連動扣款' }}
                  </span>
                  <PhCaretRight size="16" class="caret-indicator" />
                </div>
                <select v-model="newAsset.funding_account_id" class="invisible-select">
                  <option :value="null">無連動扣款 (僅作記錄)</option>
                  <option v-for="acc in accounts.filter(a => ['Bank', 'Cash', 'E-Wallet', 'OtherLiquid'].includes(a.type))" :key="acc.id" :value="acc.id">
                    {{ acc.name }} (餘額: {{ formatInvestNumber(acc.balance) }} 元)
                  </option>
                </select>
              </div>

              <!-- 同步扣除帳戶餘額 -->
              <div v-if="newAsset.funding_account_id" class="form-item-row" style="border-bottom: none;">
                <span class="row-label">同步扣除帳戶餘額</span>
                <label class="toggle-switch">
                  <input type="checkbox" v-model="syncAccountBalance" />
                  <span class="toggle-slider"></span>
                </label>
              </div>
            </div>
            
            <div class="form-card-black">
              <div class="form-item-row" style="border-bottom: none;">
                <span class="row-label">買入日期</span>
                <input v-model="newAsset.buy_date" type="date" class="input-flat-right text-right" />
              </div>
            </div>
          </template>

          <!-- Case B: Fixed Amount Cash, Bank, RealEstate, Car, Payable, Loan, Receivables etc. -->
          <template v-else>
            <div class="form-card-black">
              <div class="form-item-row">
                <span class="row-label">金額</span>
                <div class="row-value-wrapper">
                  <input v-model.number="newAsset.balance" type="number" placeholder="0" class="input-flat-right" />
                  <span class="currency-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; padding: 4px 8px; border-radius: 6px; font-size: 0.75rem; font-weight: 700;">
                    {{ newAsset.currency || 'TWD' }}
                  </span>
                </div>
              </div>
              <div class="form-item-row" style="position: relative;">
                <span class="row-label">幣別</span>
                <div class="row-value-wrapper">
                  <span class="display-val" style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">
                    {{ newAsset.currency || 'TWD' }}
                  </span>
                  <PhCaretRight size="16" class="caret-indicator" />
                </div>
                <select v-model="newAsset.currency" class="invisible-select">
                  <option value="TWD">TWD (新台幣)</option>
                  <option value="USD">USD (美金)</option>
                  <option value="JPY">JPY (日幣)</option>
                </select>
              </div>
              <div class="form-item-row">
                <span class="row-label">自定名稱</span>
                <input v-model="newAsset.name" :placeholder="'自訂名稱，預設為' + translateTypeSettings(newAsset.type)" class="input-flat-right text-right" />
              </div>

              <!-- 自訂群組 -->
              <div class="form-item-row" style="position: relative;">
                <span class="row-label">自訂群組</span>
                <div class="row-value-wrapper">
                  <span class="display-val" style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">
                    {{ newAsset.custom_group || '無群組' }}
                  </span>
                  <PhCaretRight size="16" class="caret-indicator" />
                </div>
                <select v-model="newAsset.custom_group" @change="handleCustomGroupChange('account')" class="invisible-select">
                  <option value="">無群組</option>
                  <option v-for="grp in customAccountGroupsList" :key="grp" :value="grp">{{ grp }}</option>
                  <option value="__NEW__">+ 新增群組...</option>
                </select>
              </div>
              <div class="form-item-row">
                <span class="row-label">計入圖表</span>
                <label class="toggle-switch">
                  <input type="checkbox" v-model="newAsset.include_in_chart" />
                  <span class="toggle-slider"></span>
                </label>
              </div>
              <div class="form-item-row" style="border-bottom: none;">
                <span class="row-label">備註</span>
                <input v-model="newAsset.remarks" placeholder="輸入備註" class="input-flat-right text-right" />
              </div>
            </div>

            <!-- Auto-Record bar under Case B -->
            <div style="margin-top: 24px; margin-bottom: 8px;">
              <!-- Header Row -->
              <div style="display: flex; align-items: center; justify-content: space-between; width: 100%; margin-bottom: 6px;">
                <div style="display: flex; align-items: center; gap: 8px;">
                  <PhArrowClockwise size="22" style="color: var(--color-text); opacity: 0.85;" />
                  <span style="font-size: 1.05rem; font-weight: 700; color: var(--color-text);">自動記</span>
                </div>
                <button type="button" @click="openAddAutoRecord" style="background: transparent; border: 1.5px solid var(--color-text-muted); color: var(--color-text); padding: 5px 14px; border-radius: 50px; font-size: 0.8rem; font-weight: 700; box-shadow: none; cursor: pointer; transition: all 0.2s; margin: 0; min-height: unset; height: auto;" onmouseover="this.style.background='rgba(255,255,255,0.05)'" onmouseout="this.style.background='transparent'">
                  新增自動記
                </button>
              </div>
              
              <!-- Summary Row -->
              <div style="text-align: right; font-size: 0.78rem; color: var(--color-text-muted); margin-bottom: 12px; padding-right: 4px;">
                總計：+{{ autoRecordsSummary.income }}，-{{ autoRecordsSummary.expense }}
              </div>
              
              <!-- Cards List -->
              <div v-if="newAssetAutoRecords.length > 0" style="display: flex; flex-direction: column; gap: 12px; width: 100%;">
                <div v-for="(ar, idx) in newAssetAutoRecords" :key="idx" class="auto-record-card-spec" style="position: relative; display: flex; align-items: center; justify-content: space-between; padding: 18px 20px; background: rgba(0, 0, 0, 0.02); border: 1px solid var(--color-card-border); border-radius: 18px; box-sizing: border-box; width: 100%; transition: all 0.2s; cursor: pointer;" @click="openEditAutoRecord(idx)">
                  <!-- Left Info -->
                  <div style="display: flex; flex-direction: column; align-items: flex-start; gap: 8px; text-align: left; flex: 1; min-width: 0;">
                    <div style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap; width: 100%;">
                      <!-- Type Badge -->
                      <span :style="{
                        fontSize: '0.72rem',
                        fontWeight: '700',
                        padding: '3px 8px',
                        borderRadius: '6px',
                        border: ar.type === 'income' ? '1px solid var(--color-success)' : ar.type === 'expense' ? '1px solid var(--color-accent)' : ar.type === 'dca_invest' ? '1px solid #8b5cf6' : '1px solid var(--color-primary)',
                        color: ar.type === 'income' ? 'var(--color-success)' : ar.type === 'expense' ? 'var(--color-accent)' : ar.type === 'dca_invest' ? '#a78bfa' : 'var(--color-primary)',
                        background: 'transparent'
                      }">
                        {{ ar.type === 'income' ? '固定增加' : ar.type === 'expense' ? '固定減少' : ar.type === 'dca_invest' ? '定期買股' : '定期轉帳' }}
                      </span>
                      <!-- Tag -->
                      <span v-if="ar.tag" style="font-size: 0.85rem; font-weight: 700; color: var(--color-primary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 120px;">
                        {{ ar.tag.startsWith('#') ? ar.tag : '#' + ar.tag }}
                      </span>
                      <!-- Transfer details -->
                      <span style="font-size: 0.72rem; font-weight: normal; color: var(--color-text-muted);" v-if="ar.type === 'transfer'">
                        (至: {{ accounts.find(a => a.id === ar.target_account_id)?.name || '未知' }}{{ ar.interest_rate ? ` · 利率 ${ar.interest_rate}%` : '' }})
                      </span>
                      <!-- Investment DCA details -->
                      <span style="font-size: 0.72rem; font-weight: normal; color: var(--color-text-muted);" v-if="ar.type === 'dca_invest'">
                        (標的: {{ ar.symbol || '未設定' }})
                      </span>
                    </div>
                    <!-- Date -->
                    <div style="font-size: 0.82rem; color: var(--color-text-muted); font-weight: 500;">
                      每月{{ ar.day }}日
                    </div>
                    <!-- Next Tx Capsule -->
                    <div style="background: rgba(0, 0, 0, 0.04); padding: 4px 10px; border-radius: 8px; font-size: 0.72rem; color: var(--color-text-muted); font-weight: 600;">
                      下次交易時間 {{ getNextTxDateStr(ar.day) }}
                    </div>
                  </div>
                  
                  <!-- Right Amount & Controls -->
                  <div style="display: flex; align-items: center; gap: 12px; flex-shrink: 0;">
                    <span :style="{
                      fontSize: '1.25rem',
                      fontWeight: '800',
                      color: ar.type === 'income' ? 'var(--color-success)' : 'var(--color-text)'
                    }">
                      {{ ar.type === 'income' ? '+' : '-' }}{{ ar.currency || 'TWD' }} {{ Number(ar.amount).toLocaleString('en-US', { minimumFractionDigits: 0 }) }}
                    </span>
                    <!-- Delete Button inside Card -->
                    <button type="button" @click.stop="deleteAutoRecord(idx)" style="background: rgba(224, 59, 84, 0.08); border: none; padding: 6px; border-radius: 8px; box-shadow: none; cursor: pointer; color: var(--color-danger); display: flex; align-items: center; justify-content: center; width: 26px; height: 26px; margin: 0; min-height: unset; height: auto;" onmouseover="this.style.background='rgba(224, 59, 84, 0.15)'" onmouseout="this.style.background='rgba(224, 59, 84, 0.08)'">
                      <PhTrash size="13" weight="bold" />
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </template>

        </div>

        <div v-if="saveError" class="save-error">⚠️ {{ saveError }}</div>

        <!-- Delete Button (Only when editing) -->
        <div v-if="isEditing" style="padding: 16px; margin-top: 10px;">
          <button 
            type="button" 
            @click="handleDeleteFromEdit" 
            style="width: 100%; padding: 15px; border-radius: 16px; background: rgba(239, 68, 68, 0.1); border: 1px solid rgba(239, 68, 68, 0.2); color: #ef4444; font-weight: 700; font-size: 0.95rem; cursor: pointer; transition: all 0.2s; box-shadow: none;"
          >
            刪除此項目
          </button>
        </div>
      </div>

      <!-- Step 3: Auto-Record Config page -->
      <div class="modal-content-full" v-else-if="addModalStep === 3" key="step3">
        <div class="modal-navbar">
          <button class="nav-back-circle" @click="cancelAutoRecordConfig" title="返回">
            <PhCaretLeft size="20" weight="bold" />
          </button>
          <span class="nav-title">自動記</span>
          <button class="nav-save-circle" @click="saveAutoRecordConfig()" title="確定">
            <PhCheck size="20" weight="bold" />
          </button>
        </div>

        <div class="form-body" v-if="activeAutoRecord">
          <!-- Tabs Segmented Control -->
          <div class="segmented-control" style="background-color: rgba(0, 0, 0, 0.04); border-radius: 14px; padding: 4px; display: flex;">
            <button 
              type="button" 
              class="seg-btn active-income" 
              :class="{ active: activeAutoRecord.type === 'income' }"
              style="border-radius: 10px; flex: 1;"
              @click="activeAutoRecord.type = 'income'; activeAutoRecord.target_account_id = null"
            >
              固定收入
            </button>
            <button 
              type="button" 
              class="seg-btn active-expense" 
              :class="{ active: activeAutoRecord.type === 'expense' }"
              style="border-radius: 10px; flex: 1;"
              @click="activeAutoRecord.type = 'expense'; activeAutoRecord.target_account_id = null"
            >
              固定支出
            </button>
            <button 
              type="button" 
              class="seg-btn active-transfer" 
              :class="{ active: activeAutoRecord.type === 'transfer' }"
              style="border-radius: 10px; flex: 1;"
              @click="activeAutoRecord.type = 'transfer'"
            >
              定期轉帳
            </button>
            <button 
              type="button" 
              class="seg-btn active-dca_invest" 
              :class="{ active: activeAutoRecord.type === 'dca_invest' }"
              style="border-radius: 10px; flex: 1;"
              @click="activeAutoRecord.type = 'dca_invest'; activeAutoRecord.target_account_id = null; if(!activeAutoRecord.symbol) activeAutoRecord.symbol = ''"
            >
              定期買股
            </button>
          </div>

          <!-- Card 1 -->
          <div class="form-card-black">
            <div class="form-item-row">
              <div class="row-label-group">
                <span class="row-label">金額</span>
                <span class="row-sublabel">{{ activeAutoRecord.currency || 'TWD' }}</span>
              </div>
              <div class="row-value-wrapper">
                <input v-model.number="activeAutoRecord.amount" type="number" placeholder="0" class="input-flat-right" />
                <button type="button" class="minus-circle-btn" @click="activeAutoRecord.amount = 0">
                  <PhMinusCircle size="20" weight="bold" />
                </button>
              </div>
            </div>

            <!-- DCA Currency (Only for DCA Investment type) -->
            <div v-if="activeAutoRecord.type === 'dca_invest'" class="form-item-row" style="position: relative;">
              <span class="row-label">扣款幣別</span>
              <div class="row-value-wrapper">
                <span class="display-val" style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">
                  {{ activeAutoRecord.currency || 'TWD' }}
                </span>
                <PhCaretRight size="16" class="chevron-icon" />
              </div>
              <select v-model="activeAutoRecord.currency" class="invisible-select">
                <option value="TWD">TWD (新台幣)</option>
                <option value="USD">USD (美金)</option>
              </select>
            </div>
            
            <!-- Symbol Input (Only for DCA Investment type) -->
            <div v-if="activeAutoRecord.type === 'dca_invest'" class="form-item-row">
              <div class="row-label-group">
                <span class="row-label">股票代號</span>
                <span class="row-sublabel">例如 0050.TW, VOO</span>
              </div>
              <div class="row-value-wrapper">
                <input v-model="activeAutoRecord.symbol" placeholder="請輸入代號" class="input-flat-right text-right" style="text-transform: uppercase;" />
              </div>
            </div>

            <div class="form-item-row" style="position: relative;">
              <span class="row-label">記錄日期</span>
              <div class="row-value-wrapper">
                <span class="display-val" style="color: var(--color-text-muted); font-size: 0.95rem; font-weight: 700;">每月{{ activeAutoRecord.day }}日</span>
                <PhCaretRight size="16" class="chevron-icon" />
              </div>
              <select v-model.number="activeAutoRecord.day" class="invisible-select">
                <option v-for="d in 31" :key="d" :value="d">每月{{ d }}日</option>
              </select>
            </div>

            <!-- Target Account (Only for Transfer type) -->
            <div v-if="activeAutoRecord.type === 'transfer'" class="form-item-row" style="position: relative;">
              <span class="row-label">轉入目標帳戶</span>
              <div class="row-value-wrapper">
                <span class="display-val" style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">
                  {{ accounts.find(a => a.id === activeAutoRecord.target_account_id)?.name || '請選擇帳戶' }}
                </span>
                <PhCaretRight size="16" class="chevron-icon" />
              </div>
              <select v-model="activeAutoRecord.target_account_id" class="invisible-select">
                <option :value="null" disabled>請選擇帳戶</option>
                <option 
                  v-for="acc in accounts.filter(a => a.id !== editingId)" 
                  :key="acc.id" 
                  :value="acc.id"
                >
                  {{ acc.name }} ({{ translateTypeSettings(acc.type) }})
                </option>
              </select>
            </div>

            <!-- Interest rate input for Transfer to Liability target -->
            <div v-if="activeAutoRecord.type === 'transfer' && isLiabilityAccount(activeAutoRecord.target_account_id)" class="form-item-row">
              <div class="row-label-group">
                <span class="row-label">年利率 (%)</span>
                <span class="row-sublabel">若輸入將自動計算利息與本金</span>
              </div>
              <div class="row-value-wrapper">
                <input v-model.number="activeAutoRecord.interest_rate" type="number" step="0.001" placeholder="例如 1.775 (選填)" class="input-flat-right" />
              </div>
            </div>

            <div class="form-item-row" style="border-bottom: none;">
              <span class="row-label">標籤</span>
              <input v-model="activeAutoRecord.tag" placeholder="#輸入標籤" class="input-flat-right text-right red-text red-placeholder" @input="handleTagInput" />
            </div>
          </div>

          <div class="next-time-hint">
            下次記錄時間：{{ nextRecordDateStr }}
          </div>

          <div v-if="saveError" class="save-error" style="margin-top: 16px;">⚠️ {{ saveError }}</div>

          <!-- Card 2 -->
          <div class="form-card-black">
            <div class="form-item-row" style="border-bottom: none;">
              <span class="row-label">有效期</span>
              <div class="expiry-pill-selector">
                <button type="button" class="expiry-pill" :class="{ active: activeAutoRecord.expiry === 'forever' }" @click="activeAutoRecord.expiry = 'forever'">
                  永遠
                </button>
                <button type="button" class="expiry-pill" :class="{ active: activeAutoRecord.expiry === 'custom' }" @click="activeAutoRecord.expiry = 'custom'; if(!activeAutoRecord.expiry_date) activeAutoRecord.expiry_date = new Date(new Date().setMonth(new Date().getMonth() + 12)).toISOString().split('T')[0]">
                  自訂
                </button>
              </div>
            </div>
            <!-- If custom expiry, show date picker row -->
            <div v-if="activeAutoRecord.expiry === 'custom'" class="form-item-row" style="border-bottom: none; border-top: 1px solid var(--color-card-border); display: flex; justify-content: space-between; align-items: center;">
              <span class="row-label">結束日期</span>
              <input v-model="activeAutoRecord.expiry_date" type="date" class="input-flat-right text-right" style="color: var(--color-text); font-weight: bold; border: none; background: transparent; font-family: inherit; font-size: 0.95rem;" />
            </div>
          </div>

        </div>
      </div>

      <!-- Step 4: Investment Detail View -->
      <div class="modal-content-full" v-else-if="addModalStep === 4" key="step4" style="background: var(--color-bg); min-height: 100vh;">
        <div class="modal-navbar" style="background: var(--color-bg); border-bottom: 1px solid var(--color-card-border); padding-bottom: 16px;">
          <!-- Close button X -->
          <button class="nav-back-circle" @click="closeAddModal()" title="關閉" style="background: rgba(0, 0, 0, 0.05); color: var(--color-text); width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center;">
            <PhMinusCircle size="20" weight="bold" />
          </button>
          <span class="nav-title" style="color: var(--color-text);">詳情</span>
          <!-- Pencil (Edit) in header -->
          <div style="display: flex; gap: 8px;">
            <button class="nav-back-circle" @click="editInvestmentBySymbol(selectedSymbol)" title="編輯" style="background: rgba(0, 0, 0, 0.05); color: var(--color-text); width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center;">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"></path><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path></svg>
            </button>
          </div>
        </div>

        <div v-if="selectedInvestment" class="invest-detail-container" style="padding: 0 8px;">
          <!-- Stock Header Info (TW/US icon + Name + Symbol) -->
          <div style="display: flex; align-items: center; gap: 12px; margin-top: 24px;">
            <!-- Badge Icon for region -->
            <div class="region-badge-circle" :style="{ background: selectedInvestment.currency === 'USD' ? 'rgba(92,103,245,0.1)' : 'rgba(120,57,236,0.1)', color: selectedInvestment.currency === 'USD' ? '#5c67f5' : '#7839ec', border: selectedInvestment.currency === 'USD' ? '1px solid rgba(92,103,245,0.2)' : '1px solid rgba(120,57,236,0.2)', width: '36px', height: '36px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 'bold', fontSize: '0.8rem' }">
              {{ selectedInvestment.currency === 'USD' ? 'US' : 'TW' }}
            </div>
            <div style="display: flex; flex-direction: column; text-align: left;">
              <span style="color: var(--color-text); font-size: 1.25rem; font-weight: 800;">{{ selectedInvestment.name }}</span>
              <span style="color: var(--color-text-muted); font-size: 0.85rem; font-weight: 600; margin-top: 1px;">{{ selectedInvestment.symbol }}</span>
            </div>
          </div>

          <!-- Large Balance -->
          <div style="text-align: left; margin-top: 32px; margin-bottom: 32px;">
            <div style="color: var(--color-text); font-size: 2.5rem; font-weight: 800; font-family: var(--font-display); letter-spacing: -0.02em;">
              {{ isHidden ? '••••••' : formatInvestCurrency(selectedInvestment.value, selectedInvestment.currency) }}
            </div>
          </div>

          <div style="display: flex; gap: 14px; margin-bottom: 36px;">
            <button class="pill-btn-gray" @click="openAdjustShares()" style="flex: 1; padding: 12px; border-radius: 50px; font-weight: 700; font-size: 0.95rem; background: rgba(0, 0, 0, 0.05); color: var(--color-text); border: none; cursor: pointer; transition: background 0.2s;" onmouseover="this.style.background='rgba(0, 0, 0, 0.08)'" onmouseout="this.style.background='rgba(0, 0, 0, 0.05)'">
              增減股數
            </button>
            <button class="pill-btn-white" @click="openModifyBalance()" style="flex: 1; padding: 12px; border-radius: 50px; font-weight: 700; font-size: 0.95rem; background: var(--color-primary); color: #ffffff; border: none; cursor: pointer; transition: opacity 0.2s;" onmouseover="this.style.opacity='0.9'" onmouseout="this.style.opacity='1'">
              修改餘額
            </button>
          </div>

          <!-- Change History List -->
          <div class="history-section" style="text-align: left;">
            <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0,0,0,0.06); padding-bottom: 10px; margin-bottom: 14px;">
              <span style="color: var(--color-text-muted); font-size: 0.9rem; font-weight: 700;">現有持股明細 (Lots)</span>
              <span style="color: var(--color-text-muted); font-size: 0.85rem; cursor: pointer; opacity: 0.7;">⚙️</span>
            </div>

            <!-- List of Lots -->
            <div style="display: flex; flex-direction: column; gap: 14px;">
              <div v-for="lot in selectedInvestment.lots" :key="lot.id" class="history-item-row" style="display: flex; justify-content: space-between; align-items: flex-start; padding-bottom: 14px; border-bottom: 1px solid rgba(0,0,0,0.04);">
                <div style="display: flex; flex-direction: column;">
                  <span style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">{{ lot.remarks || (lot.type === 'DCA' ? '定期定額/定期定投' : '買入持股') }}</span>
                  <span style="color: var(--color-text-muted); font-size: 0.82rem; margin-top: 4px;">
                    持有 {{ isHidden ? '••••' : formatInvestNumber(lot.quantity) }}, {{ lot.currency }} {{ isHidden ? '••••' : formatInvestNumber(lot.buy_price) }}
                  </span>
                  <span style="color: var(--color-text-muted); opacity: 0.8; font-size: 0.8rem; margin-top: 4px;">{{ formatDateDetailed(lot.buy_date || lot.created_at) }}</span>
                </div>
                <div style="display: flex; flex-direction: column; align-items: flex-end;">
                  <span style="color: #2ec173; font-size: 0.95rem; font-weight: 700;">
                    {{ isHidden ? '••••••' : formatHistoryValue(lot.quantity * lot.current_price, lot.currency) }}
                  </span>
                  <span style="color: var(--color-text-muted); font-size: 0.82rem; margin-top: 4px;">
                    現值 {{ isHidden ? '••••••' : formatHistoryValue(lot.quantity * lot.current_price, lot.currency) }}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- Delete button at the bottom of the detail container -->
          <div style="padding: 16px 0; margin-top: 24px;">
            <button 
              type="button" 
              @click="deleteInvestmentBySymbol(selectedSymbol)" 
              style="width: 100%; padding: 15px; border-radius: 16px; background: rgba(239, 68, 68, 0.1); border: 1px solid rgba(239, 68, 68, 0.2); color: #ef4444; font-weight: 700; font-size: 0.95rem; cursor: pointer; transition: all 0.2s; box-shadow: none;"
            >
              刪除此項目
            </button>
          </div>
        </div>
      </div>

      <!-- Step 5: Adjust Shares View -->
      <div class="modal-content-full" v-else-if="addModalStep === 5" key="step5" style="background: var(--color-bg); min-height: 100vh; padding: 0 16px; color: var(--color-text);">
        <!-- Header -->
        <div class="modal-navbar" style="background: var(--color-bg); padding-bottom: 16px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--color-card-border);">
          <button class="nav-back-circle" @click="addModalStep = 4" title="返回" style="background: rgba(0, 0, 0, 0.05); color: var(--color-text); width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; border: none; cursor: pointer;">
            <PhCaretLeft size="20" weight="bold" />
          </button>
          <button @click="addModalStep = 4" style="background: none; border: none; color: var(--color-text); font-size: 1rem; font-weight: bold; cursor: pointer;">
            取消
          </button>
        </div>

        <div v-if="selectedInvestment" style="text-align: left; margin-top: 16px;">
          <!-- Title & Symbol -->
          <div style="font-size: 1.25rem; font-weight: 800; color: var(--color-text);">{{ selectedInvestment.name }}</div>
          <div style="font-size: 0.85rem; color: var(--color-text-muted); margin-top: 2px; font-weight: 600;">{{ selectedInvestment.symbol }}</div>

          <!-- Quantity input -->
          <div style="margin-top: 32px; position: relative;">
            <div style="font-size: 0.9rem; color: var(--color-text-muted); font-weight: 700; margin-bottom: 8px;">股數</div>
            <div style="display: flex; align-items: baseline; border-bottom: 1px solid rgba(0, 0, 0, 0.15); padding-bottom: 8px;">
              <input 
                v-model.number="adjustSharesVal" 
                type="number" 
                placeholder="0" 
                class="reset-input"
                style="background: transparent; border: none; color: var(--color-text); font-size: 3rem; font-weight: 800; width: 100%; outline: none; font-family: var(--font-display); padding: 0 !important; margin: 0 !important;"
              />
            </div>
          </div>

          <!-- Form Fields -->
          <div style="margin-top: 24px; display: flex; flex-direction: column; gap: 18px;">
            <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding-bottom: 12px;">
              <span style="color: var(--color-text-muted); font-size: 0.95rem;">備註</span>
              <input v-model="adjustRemarks" class="reset-input" style="background: transparent; border: none; color: var(--color-text); font-size: 0.95rem; text-align: right; outline: none; width: 60%; padding: 0 !important; margin: 0 !important;" />
            </div>

            <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding-bottom: 12px;">
              <span style="color: var(--color-text-muted); font-size: 0.95rem;">價格</span>
              <div style="display: flex; align-items: center; gap: 6px;">
                <span style="background: rgba(0, 0, 0, 0.05); padding: 6px 12px; border-radius: 20px; font-size: 0.85rem; font-weight: bold; color: var(--color-text); display: flex; align-items: center;">
                  {{ selectedInvestment.currency }} 
                  <input v-model.number="adjustPrice" type="number" step="any" class="reset-input" style="background: transparent; border: none; color: var(--color-text); font-size: 0.85rem; font-weight: bold; outline: none; width: 60px; margin-left: 4px; text-align: right; padding: 0 !important; margin: 0 !important;" />
                </span>
              </div>
            </div>

            <!-- 連動帳戶 -->
            <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding-bottom: 12px; position: relative;">
              <span style="color: var(--color-text-muted); font-size: 0.95rem;">
                {{ adjustAction === 'plus' ? '扣款帳戶' : '收款帳戶' }}
              </span>
              <div style="display: flex; align-items: center; gap: 4px;">
                <span style="font-size: 0.95rem; font-weight: 700; color: var(--color-text);">
                  {{ accounts.find(a => a.id === newAsset.funding_account_id)?.name || '無連動帳戶' }}
                </span>
                <PhCaretDown size="16" style="color: var(--color-text-muted);" />
              </div>
              <select v-model="newAsset.funding_account_id" style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; opacity: 0; cursor: pointer;">
                <option :value="null">無連動帳戶 (僅作記錄)</option>
                <option v-for="acc in accounts.filter(a => ['Bank', 'Cash', 'E-Wallet', 'OtherLiquid'].includes(a.type))" :key="acc.id" :value="acc.id">
                  {{ acc.name }} (餘額: {{ formatInvestNumber(acc.balance) }} 元)
                </option>
              </select>
            </div>

            <!-- 同步更新帳戶餘額 -->
            <div v-if="newAsset.funding_account_id" style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding-bottom: 12px;">
              <span style="color: var(--color-text-muted); font-size: 0.95rem;">同步更新帳戶餘額</span>
              <label class="toggle-switch">
                <input type="checkbox" v-model="syncAccountBalance" />
                <span class="toggle-slider"></span>
              </label>
            </div>

            <!-- 手動修正實現損益 (僅在賣出時顯示) -->
            <div v-if="adjustAction === 'minus'" style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding-bottom: 12px;">
              <span style="color: var(--color-text-muted); font-size: 0.95rem;">手動修正實現損益 ({{ selectedInvestment.currency }})</span>
              <input v-model="customProfitVal" type="number" step="any" placeholder="留空使用預估值" class="reset-input" style="background: transparent; border: none; color: var(--color-text); font-size: 0.95rem; text-align: right; outline: none; width: 50%; padding: 0 !important; margin: 0 !important;" />
            </div>
          </div>

          <!-- Plus / Minus Segments -->
          <div style="display: flex; gap: 12px; margin-top: 32px;">
            <button 
              @click="adjustAction = 'plus'"
              :style="{
                flex: 1,
                padding: '16px',
                borderRadius: '16px',
                border: 'none',
                fontSize: '1.5rem',
                fontWeight: 'bold',
                cursor: 'pointer',
                background: adjustAction === 'plus' ? 'var(--color-primary)' : 'rgba(0,0,0,0.04)',
                color: adjustAction === 'plus' ? '#ffffff' : 'var(--color-text)',
                border: 'none'
              }"
            >
              +
            </button>
            <button 
              @click="adjustAction = 'minus'"
              :style="{
                flex: 1,
                padding: '16px',
                borderRadius: '16px',
                border: 'none',
                fontSize: '1.5rem',
                fontWeight: 'bold',
                cursor: 'pointer',
                background: adjustAction === 'minus' ? 'var(--color-primary)' : 'rgba(0,0,0,0.04)',
                color: adjustAction === 'minus' ? '#ffffff' : 'var(--color-text)',
                border: 'none'
              }"
            >
              -
            </button>
          </div>

          <!-- Live values -->
          <div style="margin-top: 24px; text-align: left; font-family: var(--font-display);">
            <div style="font-size: 1.1rem; font-weight: bold; color: var(--color-primary);">
              {{ adjustAction === 'plus' ? '+' : '-' }}{{ formatInvestCurrency((Number(adjustSharesVal || 0) * Number(adjustPrice || 0)), selectedInvestment.currency) }}
            </div>
            <div style="font-size: 0.9rem; color: var(--color-text-muted); margin-top: 6px; font-weight: 500;">
              餘額 {{ formatInvestCurrency(Math.max(0, selectedInvestment.quantity + (adjustAction === 'plus' ? Number(adjustSharesVal || 0) : -Number(adjustSharesVal || 0))) * Number(adjustPrice || 0), selectedInvestment.currency) }}
            </div>
            <div style="font-size: 0.9rem; color: var(--color-text-muted); margin-top: 4px; font-weight: 500;">
              持有 {{ Math.max(0, selectedInvestment.quantity + (adjustAction === 'plus' ? Number(adjustSharesVal || 0) : -Number(adjustSharesVal || 0))) }}
            </div>
          </div>

          <!-- Submit Button -->
          <button 
            @click="submitAdjustShares" 
            :disabled="!adjustSharesVal || adjustSharesVal <= 0"
            style="width: 100%; padding: 16px; border-radius: 16px; background: var(--color-primary); color: #ffffff; border: none; font-weight: bold; font-size: 1.05rem; margin-top: 36px; cursor: pointer; transition: opacity 0.2s;"
            :style="{ opacity: (!adjustSharesVal || adjustSharesVal <= 0) ? '0.4' : '1' }"
          >
            完成
          </button>
        </div>
      </div>

      <!-- Step 6: Modify Balance View -->
      <div class="modal-content-full" v-else-if="addModalStep === 6" key="step6" style="background: var(--color-bg); min-height: 100vh; padding: 0 16px; color: var(--color-text);">
        <!-- Header -->
        <div class="modal-navbar" style="background: var(--color-bg); padding-bottom: 16px; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--color-card-border);">
          <button class="nav-back-circle" @click="addModalStep = 4" title="返回" style="background: rgba(0, 0, 0, 0.05); color: var(--color-text); width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center; border: none; cursor: pointer;">
            <PhCaretLeft size="20" weight="bold" />
          </button>
          <button @click="addModalStep = 4" style="background: none; border: none; color: var(--color-text); font-size: 1rem; font-weight: bold; cursor: pointer;">
            取消
          </button>
        </div>

        <div v-if="selectedInvestment" style="text-align: left; margin-top: 16px;">
          <!-- Title & Symbol -->
          <div style="font-size: 1.25rem; font-weight: 800; color: var(--color-text);">{{ selectedInvestment.name }}</div>
          <div style="font-size: 0.85rem; color: var(--color-text-muted); margin-top: 2px; font-weight: 600;">{{ selectedInvestment.symbol }}</div>

          <!-- Quantity input -->
          <div style="margin-top: 32px; position: relative;">
            <div style="font-size: 0.9rem; color: var(--color-text-muted); font-weight: 700; margin-bottom: 8px;">股數</div>
            <div style="display: flex; align-items: baseline; border-bottom: 1px solid rgba(0, 0, 0, 0.15); padding-bottom: 8px;">
              <input 
                v-model.number="modifySharesVal" 
                type="number" 
                placeholder="0" 
                class="reset-input"
                style="background: transparent; border: none; color: var(--color-text); font-size: 3rem; font-weight: 800; width: 100%; outline: none; font-family: var(--font-display); padding: 0 !important; margin: 0 !important;"
              />
            </div>
          </div>

          <!-- Form Fields -->
          <div style="margin-top: 24px; display: flex; flex-direction: column; gap: 18px;">
            <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding-bottom: 12px;">
              <span style="color: var(--color-text-muted); font-size: 0.95rem;">備註</span>
              <input v-model="modifyRemarks" class="reset-input" style="background: transparent; border: none; color: var(--color-text); font-size: 0.95rem; text-align: right; outline: none; width: 60%; padding: 0 !important; margin: 0 !important;" />
            </div>

            <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding-bottom: 12px;">
              <span style="color: var(--color-text-muted); font-size: 0.95rem;">價格</span>
              <div style="display: flex; align-items: center; gap: 6px;">
                <span style="background: rgba(0, 0, 0, 0.05); padding: 6px 12px; border-radius: 20px; font-size: 0.85rem; font-weight: bold; color: var(--color-text); display: flex; align-items: center;">
                  {{ selectedInvestment.currency }} 
                  <input v-model.number="modifyPrice" type="number" step="any" class="reset-input" style="background: transparent; border: none; color: var(--color-text); font-size: 0.85rem; font-weight: bold; outline: none; width: 60px; margin-left: 4px; text-align: right; padding: 0 !important; margin: 0 !important;" />
                </span>
              </div>
            </div>

            <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0, 0, 0, 0.06); padding-bottom: 12px;">
              <span style="color: var(--color-text-muted); font-size: 0.95rem;">當前餘額</span>
              <span style="color: var(--color-text); font-size: 0.95rem; font-weight: 700; font-family: var(--font-display);">
                {{ formatInvestCurrency((Number(modifySharesVal || 0) * Number(modifyPrice || 0)), selectedInvestment.currency) }}
              </span>
            </div>
          </div>

          <!-- Submit Button -->
          <button 
            @click="submitModifyBalance" 
            style="width: 100%; padding: 16px; border-radius: 16px; background: var(--color-primary); color: #ffffff; border: none; font-weight: bold; font-size: 1.05rem; margin-top: 36px; cursor: pointer; transition: opacity 0.2s;"
          >
            完成
          </button>
        </div>
      </div>
      </Transition>
    </div>
    </Transition>

    <!-- ── Custom Delete Confirmation Modal ── -->
    <div v-if="showDeleteConfirm" class="modal-overlay" style="z-index: 4000; background: rgba(0, 0, 0, 0.4); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;">
      <div class="card" style="width: 90%; max-width: 320px; padding: 1.5rem; text-align: center; border: 1px solid var(--color-card-border); background: var(--color-card-bg); box-shadow: var(--shadow-lg); display: flex; flex-direction: column; gap: 1rem;">
        <h3 style="margin: 0; font-size: 1.15rem; color: var(--color-text); font-weight: 800;">確認刪除</h3>
        <p style="margin: 0; font-size: 0.9rem; color: var(--color-text-muted); line-height: 1.5;">
          {{ deleteConfirmMessage }}
        </p>
        <div style="display: flex; gap: 12px; margin-top: 0.5rem;">
          <button @click="cancelDelete" style="flex: 1; height: 40px; padding: 0; background: rgba(0, 0, 0, 0.05); color: var(--color-text); border: none; font-weight: 700; border-radius: 12px; cursor: pointer; transition: all 0.2s; box-shadow: none;" onmouseover="this.style.background='rgba(0,0,0,0.08)'" onmouseout="this.style.background='rgba(0,0,0,0.05)'">
            取消
          </button>
          <button @click="confirmDelete" style="flex: 1; height: 40px; padding: 0; background: var(--color-danger); color: white; border: none; font-weight: 700; border-radius: 12px; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 12px rgba(224, 59, 84, 0.2);" onmouseover="this.style.opacity='0.9'" onmouseout="this.style.opacity='1'">
            確認刪除
          </button>
        </div>
      </div>
    </div>

    <!-- ── Create Group Modal ── -->
    <div v-if="showCreateGroupModal" class="modal-overlay" style="z-index: 3000; background: rgba(0, 0, 0, 0.4); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;">
      <div class="card" style="width: 90%; max-width: 340px; padding: 1.5rem; border: 1px solid var(--color-card-border); background: var(--color-card-bg); box-shadow: var(--shadow-lg); display: flex; flex-direction: column; gap: 1.2rem;">
        <h3 style="margin: 0; font-size: 1.15rem; color: var(--color-text); font-weight: 800; text-align: center;">🏷️ 新增自訂群組</h3>
        <div style="display: flex; flex-direction: column; gap: 0.5rem;">
          <label style="font-size: 0.85rem; color: var(--color-text-muted); font-weight: bold; text-align: left;">群組名稱</label>
          <input v-model="newGroupName" placeholder="例如：退休基金、緊急預備金" style="width: 100%; height: 44px; padding: 0 12px; border-radius: 12px; border: 1px solid rgba(0,0,0,0.08); background: #f8fafc; color: var(--color-text); font-size: 0.95rem; outline: none; box-sizing: border-box;" />
        </div>
        <div style="display: flex; gap: 12px;">
          <button @click="showCreateGroupModal = false" style="flex: 1; height: 40px; padding: 0; background: rgba(0, 0, 0, 0.05); color: var(--color-text); border: none; font-weight: 700; border-radius: 12px; cursor: pointer; transition: all 0.2s; box-shadow: none;" onmouseover="this.style.background='rgba(0,0,0,0.08)'" onmouseout="this.style.background='rgba(0,0,0,0.05)'">
            取消
          </button>
          <button @click="submitCreateGroup" style="flex: 1; height: 40px; padding: 0; background: var(--color-primary); color: white; border: none; font-weight: 700; border-radius: 12px; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 12px rgba(26, 30, 38, 0.1);" onmouseover="this.style.opacity='0.9'" onmouseout="this.style.opacity='1'">
            儲存
          </button>
        </div>
      </div>
    </div>

    <!-- ── Manage Group Modal ── -->
    <div v-if="showManageGroupModal" class="modal-overlay" style="z-index: 3000; background: rgba(0, 0, 0, 0.4); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;">
      <div class="card" style="width: 90%; max-width: 420px; max-height: 80vh; padding: 1.5rem; border: 1px solid var(--color-card-border); background: var(--color-card-bg); box-shadow: var(--shadow-lg); display: flex; flex-direction: column; gap: 1.2rem; overflow: hidden; box-sizing: border-box;">
        <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(0,0,0,0.06); padding-bottom: 0.8rem;">
          <h3 style="margin: 0; font-size: 1.15rem; color: var(--color-text); font-weight: 800;">⚙️ 管理{{ activeGroupType === 'account' ? '帳戶' : '投資' }}群組：{{ selectedGroupToManage }}</h3>
          <button @click="showManageGroupModal = false" style="background: none; border: none; color: var(--color-text-muted); cursor: pointer; padding: 4px; font-size: 1.5rem; line-height: 1; display: flex; align-items: center; justify-content: center;">
            &times;
          </button>
        </div>

        <!-- Add items to group (Premium Checkbox List) -->
        <div style="display: flex; flex-direction: column; gap: 0.8rem; background: var(--color-bg-alt, rgba(0,0,0,0.015)); padding: 1.2rem; border-radius: 16px; border: 1px solid rgba(0,0,0,0.03); box-sizing: border-box;">
          <label style="font-size: 0.85rem; color: var(--color-text); font-weight: 800; text-align: left; display: block; letter-spacing: 0.02em;">選擇要加入的項目</label>
          
          <!-- Scrollable Checkbox List -->
          <div style="
            max-height: 180px;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: 8px;
            padding: 2px 4px 2px 2px;
            box-sizing: border-box;
          ">
            <div v-if="getAvailableItemsForGroup.length === 0" style="text-align: center; color: var(--color-text-muted); font-size: 0.85rem; padding: 2rem 0; opacity: 0.7; font-weight: 600;">
              🎉 所有項目都已在此群組中
            </div>
            
            <div 
              v-else 
              v-for="item in getAvailableItemsForGroup" 
              :key="item.id" 
              style="
                display: flex !important;
                align-items: center !important;
                justify-content: flex-start !important;
                gap: 12px !important;
                padding: 10px 14px !important;
                border-radius: 12px !important;
                background: var(--color-card-bg, #ffffff) !important;
                border: 1px solid rgba(0,0,0,0.06) !important;
                box-shadow: 0 1px 3px rgba(0,0,0,0.01) !important;
                transition: all 0.2s ease !important;
                box-sizing: border-box !important;
                width: 100% !important;
              "
              onmouseover="this.style.transform='translateY(-1px)'; this.style.borderColor='rgba(92,103,245,0.35)'; this.style.boxShadow='0 4px 12px rgba(0,0,0,0.03)';"
              onmouseout="this.style.transform='none'; this.style.borderColor='rgba(0,0,0,0.06)'; this.style.boxShadow='0 1px 3px rgba(0,0,0,0.01)';"
            >
              <input 
                type="checkbox" 
                :id="'group-item-' + item.id"
                :value="JSON.stringify({id: item.id, type: item.type})" 
                v-model="selectedItemsToAddToGroup"
                style="
                  width: 18px !important;
                  height: 18px !important;
                  border-radius: 6px !important;
                  border: 1.5px solid rgba(0,0,0,0.15) !important;
                  cursor: pointer !important;
                  accent-color: #5c67f5 !important;
                  flex-shrink: 0 !important;
                  margin: 0 !important;
                "
              />
              <label 
                :for="'group-item-' + item.id"
                style="
                  font-weight: 600 !important;
                  font-size: 0.88rem !important;
                  color: var(--color-text) !important;
                  cursor: pointer !important;
                  text-align: left !important;
                  white-space: nowrap !important;
                  overflow: hidden !important;
                  text-overflow: ellipsis !important;
                  flex: 1 !important;
                  min-width: 0 !important;
                  margin: 0 !important;
                  padding: 0 !important;
                  background: transparent !important;
                  border: none !important;
                  display: inline-block !important;
                "
              >
                {{ item.name }}
              </label>
            </div>
          </div>

          <button 
            @click="addSelectedItemsToGroup" 
            style="
              height: 42px;
              width: 100%;
              background: linear-gradient(135deg, #5c67f5 0%, #4650d1 100%);
              color: white;
              border: none;
              font-weight: 800;
              font-size: 0.9rem;
              border-radius: 12px;
              cursor: pointer;
              box-shadow: 0 4px 15px rgba(92,103,245,0.25);
              transition: all 0.2s ease;
            "
            :style="{ 
              opacity: selectedItemsToAddToGroup.length === 0 ? 0.5 : 1, 
              cursor: selectedItemsToAddToGroup.length === 0 ? 'not-allowed' : 'pointer',
              boxShadow: selectedItemsToAddToGroup.length === 0 ? 'none' : '0 4px 15px rgba(92,103,245,0.25)'
            }"
            :disabled="selectedItemsToAddToGroup.length === 0"
            onmouseover="if(!this.disabled) { this.style.transform='translateY(-1px)'; this.style.boxShadow='0 6px 20px rgba(92,103,245,0.35)'; }"
            onmouseout="this.style.transform='none'; this.style.boxShadow=this.disabled ? 'none' : '0 4px 15px rgba(92,103,245,0.25)';"
          >
            加入已選項目 ({{ selectedItemsToAddToGroup.length }})
          </button>
        </div>

        <!-- Current Members List -->
        <div style="flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 0.6rem; min-height: 150px; padding-right: 4px;">
          <label style="font-size: 0.85rem; color: var(--color-text-muted); font-weight: bold; text-align: left; display: block;">群組成員列表 ({{ getGroupMembers(selectedGroupToManage, activeGroupType).length }})</label>
          
          <div v-if="getGroupMembers(selectedGroupToManage, activeGroupType).length === 0" style="text-align: center; color: var(--color-text-muted); font-size: 0.85rem; padding: 2rem 0; opacity: 0.7;">
            此群組目前沒有任何項目
          </div>

          <div v-else v-for="member in getGroupMembers(selectedGroupToManage, activeGroupType)" :key="member.id" style="display: flex; justify-content: space-between; align-items: center; padding: 8px 12px; background: white; border: 1px solid rgba(0,0,0,0.04); border-radius: 10px; box-shadow: 0 1px 2px rgba(0,0,0,0.01);">
            <div style="display: flex; align-items: center; gap: 8px;">
              <span style="font-size: 1.1rem;">{{ member.type === 'account' ? '🏦' : '📈' }}</span>
              <span style="font-size: 0.9rem; color: var(--color-text); font-weight: 600;">{{ member.name }}</span>
            </div>
            <button @click="removeItemFromGroup(member.id, member.type)" style="background: none; border: none; color: var(--color-danger); font-size: 0.8rem; font-weight: bold; cursor: pointer; padding: 4px 8px; border-radius: 6px; transition: all 0.2s;" onmouseover="this.style.background='rgba(224, 59, 84, 0.05)'" onmouseout="this.style.background='none'">
              移除
            </button>
          </div>
        </div>

        <div style="border-top: 1px solid rgba(0,0,0,0.06); padding-top: 0.8rem; text-align: right; flex-shrink: 0;">
          <button @click="showManageGroupModal = false" style="height: 38px; padding: 0 20px; background: rgba(0, 0, 0, 0.05); color: var(--color-text); border: none; font-weight: 700; border-radius: 10px; cursor: pointer;">
            關閉
          </button>
        </div>
      </div>
    </div>

    <!-- ── 5. Income & Expense Statistics Modal (收支統計) ── -->
    <Transition name="modal-slide">
      <div v-if="showStatsModal" class="modal-overlay" @click.self="showStatsModal = false">
        <div class="modal-content-full" style="background: var(--color-bg); min-height: 100vh;">
          <!-- Navbar -->
          <div class="modal-navbar" style="background: var(--color-bg); border-bottom: 1px solid var(--color-card-border); padding-bottom: 16px;">
            <!-- Spacer to keep title centered -->
            <div style="width: 36px;"></div>
            <span class="nav-title" style="color: var(--color-text);">收支統計</span>
            <!-- Close button X -->
            <button class="nav-back-circle" @click="showStatsModal = false" title="關閉" style="background: rgba(0, 0, 0, 0.05); color: var(--color-text); width: 36px; height: 36px; border-radius: 50%; display: flex; align-items: center; justify-content: center;">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
            </button>
          </div>

          <div class="form-body" style="padding: 16px 0;">
            <!-- Segmented Control for Stats Type -->
            <div class="segmented-control" style="background-color: rgba(0, 0, 0, 0.04); border-radius: 20px; padding: 4px; display: flex; margin-bottom: 24px;">
              <button 
                type="button" 
                class="seg-btn" 
                :class="{ 'active-invest': statsType === 'invest' }"
                style="border-radius: 16px; flex: 1; font-weight: 700; height: 40px;"
                @click="statsType = 'invest'"
              >
                投資變動
              </button>
              <button 
                type="button" 
                class="seg-btn" 
                :class="{ 'active-liquid': statsType === 'liquid' }"
                style="border-radius: 16px; flex: 1; font-weight: 700; height: 40px;"
                @click="statsType = 'liquid'"
              >
                流動資金
              </button>
            </div>

            <!-- Summary Section -->
            <div style="text-align: left; padding: 0 8px; margin-bottom: 24px;">
              <div style="font-size: 0.85rem; color: var(--color-text-muted); font-weight: bold; margin-bottom: 8px;">
                {{ statsSummaryText.title }}
              </div>
              <div style="font-size: 1.1rem; font-weight: 800; color: var(--color-text); line-height: 1.5;">
                {{ statsSummaryText.desc1 }}<br/>{{ statsSummaryText.desc2 }}
              </div>
            </div>

            <!-- Legend Section -->
            <div style="display: flex; gap: 24px; align-items: center; margin-bottom: 24px; padding-left: 8px;">
              <template v-if="statsType === 'invest'">
                <div style="display: flex; align-items: center; gap: 6px; font-size: 0.82rem; font-weight: bold; color: var(--color-text);">
                  <span style="display: inline-block; width: 12px; height: 12px; background: #ccd7f5; border-radius: 2px;"></span>
                  帳戶改變
                </div>
                <div style="display: flex; align-items: center; gap: 6px; font-size: 0.82rem; font-weight: bold; color: var(--color-text);">
                  <span style="display: inline-block; width: 12px; height: 12px; background: #5c67f5; border-radius: 2px;"></span>
                  持倉盈虧
                </div>
              </template>
              <template v-else>
                <div style="display: flex; align-items: center; gap: 6px; font-size: 0.82rem; font-weight: bold; color: var(--color-text);">
                  <span style="display: inline-block; width: 12px; height: 12px; background: #2ebd59; border-radius: 2px;"></span>
                  收入
                </div>
                <div style="display: flex; align-items: center; gap: 6px; font-size: 0.82rem; font-weight: bold; color: var(--color-text);">
                  <span style="display: inline-block; width: 12px; height: 12px; background: #d1d5db; border-radius: 2px;"></span>
                  支出
                </div>
              </template>
            </div>

            <!-- Bar Chart Container -->
            <div style="height: 280px; position: relative; margin-bottom: 32px; padding: 0 4px;">
              <Bar :data="statsChartData" :options="statsChartOptions" />
            </div>

            <!-- Time Filter Selector (matching design exactly) -->
            <div style="display: flex; background: rgba(0, 0, 0, 0.04); padding: 4px; border-radius: 25px; gap: 4px; margin-bottom: 20px;">
              <button 
                v-for="time in [
                  { label: '5周', value: '5W' },
                  { label: '6月', value: '6M' },
                  { label: '1年', value: '1Y' },
                  { label: '年初至今', value: 'YTD' },
                  { label: '4年', value: '4Y' }
                ]"
                :key="time.value"
                @click="statsTimeFilter = time.value"
                :style="{
                  flex: 1,
                  padding: '10px 0',
                  borderRadius: '20px',
                  border: 'none',
                  fontSize: '0.82rem',
                  fontWeight: '700',
                  cursor: 'pointer',
                  background: statsTimeFilter === time.value ? '#ffffff' : 'transparent',
                  color: statsTimeFilter === time.value ? 'var(--color-text)' : 'var(--color-text-muted)',
                  boxShadow: statsTimeFilter === time.value ? '0 2px 4px rgba(0,0,0,0.05)' : 'none'
                }"
              >
                {{ time.label }}
              </button>
            </div>

          </div>
        </div>
      </div>
    </Transition>

    <!-- ── Custom Group Detail Modal (自訂群組詳情) ── -->
    <Transition name="modal-slide">
      <div v-if="activeCustomGroup" class="modal-overlay" style="background: var(--color-bg); min-height: 100vh;">
        <!-- Header / Navbar -->
        <div class="modal-navbar" style="background: var(--color-bg); padding: 16px 18px;">
          <button class="nav-back-circle" @click="closeCustomGroupDetail" title="返回">
            <component :is="PhCaretLeft" size="20" weight="bold" />
          </button>
          <span class="nav-title" style="color: var(--color-text);">{{ activeCustomGroup }}</span>
          <div style="display: flex; gap: 8px;">
            <button class="nav-save-circle" @click="manageGroup(activeCustomGroup, activeCustomGroupCategory === 'invest' ? 'invest' : 'account')" title="管理群組成員">
              <component :is="PhPlus" size="18" weight="bold" style="color: var(--color-primary);" />
            </button>
          </div>
        </div>

        <div class="modal-content-full" style="padding: 0 18px 40px 18px;">
          <!-- Group Sum Value -->
          <div style="display: flex; flex-direction: column; align-items: flex-end; margin-bottom: 20px;">
            <div style="display: flex; align-items: center; font-weight: 700; color: var(--color-text-muted); font-size: 0.95rem;">
              <span>合計 TWD </span>
              <span style="font-family: var(--font-display); font-size: 1.5rem; font-weight: 800; color: var(--color-text); margin-left: 8px;">
                {{ isHidden ? '••••••' : formatCurrency(Math.round(activeGroupItems.reduce((sum, item) => sum + (activeCustomGroupCategory === 'invest' ? item.valueTwd : item.balance), 0))).replace('$', '') }}
              </span>
            </div>
            <!-- Group ROI Display -->
            <div v-if="activeCustomGroupCategory === 'invest'" style="font-size: 0.85rem; font-weight: 700; margin-top: 4px;" :style="{ color: activeCustomGroupPnL >= 0 ? '#2ebd59' : '#ff453a' }">
              群組績效：{{ activeCustomGroupPnL >= 0 ? '+' : '' }}{{ isHidden ? '••••' : activeCustomGroupPnL.toLocaleString('zh-TW', { minimumFractionDigits: 0, maximumFractionDigits: 0 }) }} ({{ activeCustomGroupPnLPct >= 0 ? '+' : '' }}{{ activeCustomGroupPnLPct.toFixed(2) }}%)
            </div>
          </div>

          <!-- Items list in this group -->
          <div style="display: flex; flex-direction: column; gap: 10px;">
            <template v-if="activeCustomGroupCategory === 'invest'">
              <div 
                v-for="item in activeGroupItems" 
                :key="item.symbol" 
                class="sub-item-card" 
                @click.stop="openInvestmentDetail(item.symbol)" 
                style="cursor: pointer;"
              >
                <!-- Circular Percentage Badge (showing percentage of this group) -->
                <div class="sub-item-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; font-weight: 800;">
                  {{ Math.round(item.groupPercentage) }}%
                </div>
                
                <!-- Details -->
                <div class="sub-item-info">
                  <div class="sub-item-name">{{ item.name }}</div>
                  <div class="sub-item-desc" style="display: flex; align-items: center; flex-wrap: wrap;">
                    <span>持有 {{ isHidden ? '••••' : item.qty }}, {{ item.currency }} {{ isHidden ? '••••' : item.current_price }}</span>
                    <!-- Individual Stock ROI inside group -->
                    <span v-if="item.pnlPct !== undefined" :style="{ color: item.pnl >= 0 ? '#2ebd59' : '#ff453a', fontWeight: 'bold', marginLeft: '6px' }">
                      {{ item.pnl >= 0 ? '+' : '' }}{{ isHidden ? '••••' : Math.round(item.pnl).toLocaleString('zh-TW') }} ({{ item.pnl >= 0 ? '+' : '' }}{{ item.pnlPct.toFixed(2) }}%)
                    </span>
                  </div>
                </div>

                <!-- Value & Date -->
                <div class="sub-item-right">
                  <div class="sub-item-val">
                    {{ isHidden ? '••••••' : formatCurrency(Math.round(item.valueTwd)).replace('$', '') }}
                  </div>
                  <div class="sub-item-date">{{ formatDate(item.price_updated_at) }}</div>
                </div>
              </div>
            </template>
            <template v-else>
              <div 
                v-for="item in activeGroupItems" 
                :key="item.id" 
                class="sub-item-card" 
                @click.stop="editAccount(item)" 
                style="cursor: pointer;"
              >
                <!-- Circular Percentage Badge (showing percentage of this group) -->
                <div class="sub-item-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; font-weight: 800;">
                  {{ Math.round(item.groupPercentage) }}%
                </div>
                
                <!-- Details -->
                <div class="sub-item-info">
                  <div style="display: flex; align-items: center; gap: 6px;">
                    <component :is="getTypeIconAndColor(item.type).icon" :style="{ color: getTypeIconAndColor(item.type).color }" size="16" weight="duotone" />
                    <span class="sub-item-name" style="font-weight: 600; color: var(--color-text);">{{ item.name }}</span>
                  </div>
                  <div class="sub-item-desc">
                    {{ translateTypeSettings(item.type) }}
                  </div>
                </div>

                <!-- Value & Icons -->
                <div class="sub-item-right">
                  <div class="sub-item-val" :style="{ color: activeCustomGroupCategory === 'liab' ? 'var(--color-danger)' : 'var(--color-text)' }">
                    <span v-if="activeCustomGroupCategory === 'liab'">-</span>
                    <span>{{ isHidden ? '••••••' : formatCurrency(item.balance).replace('$', '') }}</span>
                  </div>
                  <div class="sub-item-date" style="display: flex; align-items: center; gap: 4px; justify-content: flex-end;">
                    <span v-if="item.auto_record && item.auto_record.enabled" class="sub-item-sync-icon" title="自動記帳啟用" style="font-size: 0.8rem;">🔄</span>
                  </div>
                </div>
              </div>
            </template>
          </div>
        </div>
      </div>
    </Transition>

    <!-- Smart Flow Analysis Modal -->
    <Transition name="modal-slide">
      <div v-if="showFlowAnalysisModal" class="modal-overlay" style="z-index: 2200;">
        <!-- Navbar matching native mobile app screenshot -->
        <div class="modal-navbar">
          <button class="nav-back-circle" @click="showFlowAnalysisModal = false" title="關閉">
            <PhCaretLeft size="20" weight="bold" />
          </button>
          <span class="nav-title">資金流動明細</span>
          <div class="nav-placeholder"></div>
        </div>

        <div class="modal-content-full" v-if="moneyFlowAnalysis">
          <!-- Premium Summary Header -->
          <div style="display: flex; flex-direction: column; align-items: center; text-align: center; margin: 24px 0 28px 0; border-bottom: 1px dashed var(--color-card-border); padding-bottom: 24px;">
            <div style="font-size: 1.25rem; font-weight: 800; color: var(--color-text);">{{ moneyFlowAnalysis.title }}</div>
            <div style="font-size: 0.85rem; color: var(--color-text-muted); margin-top: 10px; line-height: 1.6; padding: 0 16px; font-weight: 500;">
              {{ moneyFlowAnalysis.summary }}
            </div>
          </div>

          <!-- Realized profit/loss badge if any -->
          <div 
            v-if="moneyFlowAnalysis.tradeProfitText" 
            style="
              margin-bottom: 28px; 
              border-radius: 12px; 
              padding: 12px 16px; 
              display: flex; 
              align-items: center; 
              background: rgba(0, 0, 0, 0.015);
              border: 1px solid var(--color-card-border);
            "
          >
            <div style="display: flex; flex-direction: column; text-align: left; width: 100%;">
              <span style="font-size: 0.72rem; color: var(--color-text-muted); font-weight: 800; letter-spacing: 0.5px; text-transform: uppercase; margin-bottom: 4px;">本期交易損益</span>
              <span 
                style="font-size: 0.95rem; font-weight: 800;"
                :style="{ color: moneyFlowAnalysis.tradeProfitText.includes('獲利') ? 'var(--color-success)' : 'var(--color-danger)' }"
              >
                {{ moneyFlowAnalysis.tradeProfitText.replace('（', '').replace('）', '') }}
              </span>
            </div>
          </div>

          <!-- Section 1: Accounts Flow -->
          <div v-if="moneyFlowAnalysis.accountsFlow && moneyFlowAnalysis.accountsFlow.length > 0" style="margin-bottom: 28px; text-align: left;">
            <div style="font-size: 0.75rem; font-weight: 800; color: var(--color-text-muted); margin-bottom: 10px; border-left: 2.5px solid var(--color-primary); padding-left: 8px; letter-spacing: 0.5px; text-transform: uppercase;">
              帳戶餘額變動
            </div>
            <div class="settings-table-list" style="background: rgba(0, 0, 0, 0.015); border: 1px solid var(--color-card-border); border-radius: 12px; padding: 4px 12px;">
              <div v-for="ac in moneyFlowAnalysis.accountsFlow" :key="ac.name" class="settings-table-item" style="cursor: default; padding: 10px 0; border-bottom: 1px solid rgba(0, 0, 0, 0.03); justify-content: space-between;" onmouseover="this.style.background='transparent'">
                <div class="item-meta" style="text-align: left;">
                  <span class="item-name" style="font-size: 0.82rem; font-weight: 700; color: var(--color-text);">{{ ac.name }}</span>
                </div>
                <div class="item-right-wrap">
                  <span :style="{ color: ac.diff >= 0 ? 'var(--color-success)' : 'var(--color-danger)', fontWeight: '800', fontSize: '0.85rem', fontFamily: 'Outfit, sans-serif' }">
                    {{ ac.diff >= 0 ? '+' : '' }}{{ formatInvestNumber(ac.diff) }} 元
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- Section 2: Invest Flow -->
          <div v-if="moneyFlowAnalysis.investFlow && moneyFlowAnalysis.investFlow.length > 0" style="margin-bottom: 32px; text-align: left;">
            <div style="font-size: 0.75rem; font-weight: 800; color: var(--color-text-muted); margin-bottom: 10px; border-left: 2.5px solid #a855f7; padding-left: 8px; letter-spacing: 0.5px; text-transform: uppercase;">
              投資資金流向軌跡
            </div>
            <div style="display: flex; flex-direction: column; gap: 10px;">
              <div v-for="(item, idx) in moneyFlowAnalysis.investFlow" :key="idx" 
                   style="display: flex; flex-direction: column; gap: 6px; padding: 12px 16px; border-radius: 12px; border: 1px solid var(--color-card-border); background: rgba(0, 0, 0, 0.015);">
                <div style="display: flex; align-items: center; justify-content: space-between;">
                  <span style="font-size: 0.82rem; font-weight: 800; color: var(--color-text);">
                    {{ item.type === 'sell' ? '賣出變現匯入' : '資金流入股市' }}
                  </span>
                  <span :style="{
                    display: 'inline-block',
                    padding: '2px 6px',
                    borderRadius: '4px',
                    fontSize: '0.68rem',
                    fontWeight: '800',
                    color: item.type === 'sell' ? 'var(--color-success)' : 'var(--color-primary)',
                    background: item.type === 'sell' ? 'rgba(46, 189, 89, 0.08)' : 'rgba(92, 103, 245, 0.08)'
                  }">
                    {{ item.type === 'sell' ? '賣出' : '買入' }}
                  </span>
                </div>
                <div style="font-size: 0.8rem; color: var(--color-text-muted); font-weight: 500; margin-top: 2px;">
                  <template v-if="item.type === 'buy'">
                    從 <strong style="color: var(--color-text); font-weight: 700;">{{ item.accountName }}</strong> 流出 ➔ <span style="color: var(--color-primary); font-weight: 700;">{{ item.stockDetails }}</span>
                  </template>
                  <template v-else>
                    變現 <span style="color: var(--color-success); font-weight: 700;">{{ item.stockDetails }}</span> ➔ 匯入 <strong style="color: var(--color-text); font-weight: 700;">{{ item.accountName }}</strong>
                  </template>
                </div>
              </div>
            </div>
          </div>

          <!-- Bottom Close Button -->
          <button 
            @click="showFlowAnalysisModal = false"
            style="
              width: 100%; 
              padding: 14px; 
              border-radius: 12px; 
              background: rgba(0, 0, 0, 0.04); 
              color: var(--color-text); 
              font-weight: 700; 
              border: 1px solid var(--color-card-border); 
              cursor: pointer; 
              font-size: 0.9rem; 
              margin-top: 12px; 
              box-shadow: none;
              min-height: unset;
              height: auto;
            "
            onmouseover="this.style.background='rgba(0, 0, 0, 0.08)'"
            onmouseout="this.style.background='rgba(0, 0, 0, 0.04)'"
          >
            關閉
          </button>
        </div>
      </div>
    </Transition>

    <!-- Floating Bottom Navigation -->
    <BottomNav :currentTab="currentTab" @update:currentTab="handleBottomNavClick" />

  </div>

  <div class="dashboard-container loader-container" v-else>
    <div class="loading-spinner"></div>
    <span class="loader-text">同步財務數據中...</span>
  </div>
</template>

<style scoped>
.dashboard-container {
  width: 100%;
  max-width: 100%;
  margin: 0 auto;
  height: 100%;
  height: 100dvh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  position: relative;
  background-color: var(--color-bg);
  padding: 0;
}

.tab-view-content {
  flex: 1;
  overflow-y: auto;
  padding: 1.5rem 1.25rem 120px 1.25rem;
  display: flex;
  flex-direction: column;
  -webkit-overflow-scrolling: touch;
  max-width: 600px;
  width: 100%;
  margin: 0 auto;
  box-sizing: border-box;
}


.loader-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--color-text-muted);
  gap: 12px;
  height: 100%;
  height: 100dvh;
}

.loader-text {
  font-size: 0.9rem;
  font-weight: 500;
  letter-spacing: 0.05em;
}

/* 頂部淨資產 Header */
.top-balance-header {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  margin-bottom: 2rem;
  text-align: left;
}

.balance-left {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.balance-title {
  font-size: 0.88rem;
  font-weight: 700;
  color: var(--color-text);
  letter-spacing: 0.02em;
}

.privacy-btn {
  background: none;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 0 !important;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: none !important;
}

.privacy-btn:hover {
  color: var(--color-text);
  background: rgba(0, 0, 0, 0.03);
}

.balance-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
  margin-top: 0.25rem;
}

.balance-amount {
  font-family: var(--font-display);
  font-size: 2.2rem;
  font-weight: 800;
  color: var(--color-text);
  letter-spacing: -0.02em;
}

.add-circular-btn {
  background: #cce3ff;
  border: none;
  color: #1e80ff;
  width: 42px;
  height: 42px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: none !important;
  padding: 0 !important;
}

.add-circular-btn:hover {
  background: #b2d5ff;
  transform: scale(1.05);
}

.add-circular-btn:active {
  transform: scale(0.95);
}

/* 側邊彩色佔比條佈局 */
.main-layout {
  display: flex;
  gap: 16px;
  align-items: stretch;
  min-width: 0;
  max-width: 100%;
}

.left-bar-container {
  width: 54px;
  border-top-right-radius: 28px;
  border-bottom-right-radius: 28px;
  border-top-left-radius: 0;
  border-bottom-left-radius: 0;
  overflow: hidden;
  background: #f1f3f7;
  display: flex;
  flex-direction: column;
  flex-shrink: 0;
  margin-left: -1.25rem;
  transition: all 0.3s ease;
}

@media (max-width: 480px) {
  .left-bar-container {
    width: 36px;
    margin-left: -0.75rem;
    border-top-right-radius: 18px;
    border-bottom-right-radius: 18px;
  }
  .main-layout {
    gap: 12px;
  }
  .tab-view-content {
    padding: 1.5rem 0.75rem 120px 0.75rem !important;
  }
  .group-header-card {
    padding: 1.1rem 1.1rem !important;
  }
  .expanded-header {
    padding: 0.85rem 1.1rem !important;
  }
  .group-card {
    padding: 1.1rem 1.1rem !important;
  }
}

.bar-segment {
  width: 100%;
  transition: height 0.4s ease;
}
.segment-liquid { background-color: #5ebd74; }
.segment-invest { background-color: #5c67f5; }
.segment-fixed { background-color: #3a59cc; }
.segment-receivable { background-color: #8ba4e8; }

.list-column {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 1rem;
  min-width: 0;
}

/* Grouped Card Style */
.group-card {
  background: var(--color-card-bg);
  border-radius: var(--radius-lg);
  padding: 1.2rem 1.4rem;
  box-shadow: var(--shadow-md);
  display: flex;
  flex-direction: column;
  gap: 8px;
  border: 1px solid rgba(0, 0, 0, 0.015);
  text-align: left;
}

.group-card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.group-title {
  font-size: 1.15rem;
  font-weight: 800;
  color: var(--color-text);
}

.group-value {
  font-family: var(--font-display);
  font-size: 1.3rem;
  font-weight: 800;
  color: var(--color-text);
  letter-spacing: -0.01em;
}

.group-card-body {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
}

.group-subtitle {
  font-size: 0.78rem;
  color: var(--color-text-muted);
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 70%;
}

.group-date {
  font-size: 0.72rem;
  color: var(--color-text-muted);
  opacity: 0.85;
}

.border-red-accent {
  border-left: 4px solid var(--color-danger);
}
.text-red { color: var(--color-danger) !important; }
.text-receivable-color { color: #567ef5 !important; }

/* Unified Grouped Card Styles */
.group-wrapper {
  background: transparent !important;
  box-shadow: none !important;
  border: none !important;
  overflow: visible !important;
  display: flex;
  flex-direction: column;
}

.group-header-card {
  padding: 1.25rem 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 12px;
  background: #ffffff !important;
  color: var(--color-text);
  border-radius: 24px !important;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.03) !important;
  border: 1px solid rgba(0, 0, 0, 0.015) !important;
  transition: padding 0.25s cubic-bezier(0.32, 0.94, 0.6, 1), border-radius 0.25s ease, box-shadow 0.25s ease, background-color 0s;
}

.expanded-header {
  padding: 0.85rem 1.5rem !important;
  border-radius: 24px !important;
}

.bg-liquid { background-color: #5ebd74 !important; }
.bg-invest { background-color: #5c67f5 !important; }
.bg-fixed { background-color: #3a59cc !important; }
.bg-receivable { background-color: #8ba4e8 !important; }
.bg-liab { background-color: #e03b54 !important; }

.card-header-main-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  width: 100%;
}

.card-header-sub-row {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  width: 100%;
}

.card-subtitle-col {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  max-width: 65%;
  min-width: 0;
}

.group-title-text {
  font-family: var(--font-family);
  font-size: 1.35rem;
  font-weight: 700;
  color: #1a1a1a !important;
  letter-spacing: -0.01em;
}

.group-value-text {
  font-family: var(--font-display);
  font-size: 1.65rem;
  font-weight: 800;
  color: #1a1a1a !important;
  letter-spacing: -0.02em;
}

.group-desc-subtitle {
  font-size: 0.95rem;
  color: #9e9e9e;
  font-weight: 500;
  text-align: left;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  width: 100%;
}

.group-update-date {
  font-size: 0.8rem;
  color: #9e9e9e;
  font-weight: 500;
}

.three-dots-handle {
  display: flex;
  gap: 5px;
  margin-top: 8px;
  padding-left: 2px;
}

.three-dots-handle .dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background-color: #e0e0e0;
}

.liab-val-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.liab-minus-icon {
  color: #1a1a1a !important;
}

.group-body {
  padding: 0 0 10px 0 !important;
  display: flex;
  flex-direction: column;
}

.sub-item-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 18px !important;
  background: #ffffff !important;
  border-radius: 20px !important;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.02) !important;
  border: 1px solid rgba(0, 0, 0, 0.01) !important;
  margin-bottom: 10px !important;
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}

.sub-item-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.04) !important;
}

.sub-item-badge {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: rgba(92, 103, 245, 0.06);
  color: #5c67f5;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--font-display);
  font-size: 0.76rem;
  font-weight: 800;
  flex-shrink: 0;
}

.sub-item-info {
  flex: 1;
  text-align: left;
}

.sub-item-name {
  font-family: var(--font-family);
  font-size: 1.05rem;
  font-weight: 600;
  color: var(--color-text);
  letter-spacing: -0.01em;
}

.sub-item-desc {
  font-family: var(--font-family);
  font-size: 0.78rem;
  color: var(--color-text-muted);
  margin-top: 3px;
  font-weight: 500;
}

.sub-item-right {
  text-align: right;
}

.sub-item-val {
  font-family: var(--font-display);
  font-size: 1.15rem;
  font-weight: 700;
  color: var(--color-text);
  letter-spacing: -0.01em;
}

.sub-item-date {
  font-size: 0.68rem;
  color: var(--color-text-muted);
  margin-top: 2px;
  opacity: 0.8;
}

/* 歷史趨勢走勢圖 */
.flex-grow-trend {
  justify-content: center;
}

.trend-card {
  padding: 1.5rem;
  background: var(--color-card-bg);
  border: 1px solid rgba(0,0,0,0.015);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-md);
  text-align: left;
}

.trend-card-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 1.5rem;
}

.trend-section-title {
  margin: 0;
  font-size: 1.05rem;
  font-weight: 800;
}

.time-selector {
  display: flex;
  background: rgba(0, 0, 0, 0.03);
  border-radius: 8px;
  padding: 2px;
}

.time-btn {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  font-size: 0.72rem;
  font-weight: 700;
  padding: 4px 10px;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.2s ease;
  box-shadow: none !important;
}

.time-btn.active {
  background: #ffffff;
  color: var(--color-primary);
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.05) !important;
}

.chart-container {
  position: relative;
  height: 260px;
  width: 100%;
}

/* 管理設定頁面 */
.settings-header-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.5rem;
  text-align: left;
}
.settings-header-row h3 { margin: 0; font-size: 1.1rem; font-weight: 800; }

.icon-text-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  background: #ffffff;
  border: 1px solid rgba(0,0,0,0.08);
  color: var(--color-text-muted);
  font-size: 0.78rem;
  font-weight: 600;
  padding: 6px 12px;
  border-radius: 20px;
  box-shadow: none !important;
}
.icon-text-btn:hover { color: var(--color-text); border-color: rgba(0,0,0,0.15); }
.spin { animation: rotate 1s linear infinite; }

.settings-section {
  text-align: left;
}
.settings-section .section-title {
  margin: 0 0 1rem 0;
  font-size: 0.88rem;
  font-weight: 700;
  color: var(--color-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.settings-table-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.settings-table-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 12px;
  border-bottom: 1px solid rgba(0, 0, 0, 0.04);
  cursor: pointer;
  transition: background-color 0.2s ease;
  border-radius: 8px;
}
.settings-table-item:hover {
  background-color: rgba(0, 0, 0, 0.03);
}
.settings-table-item:last-child { border-bottom: none; }

.item-meta { display: flex; flex-direction: column; gap: 2px; }
.item-name { font-size: 0.88rem; font-weight: 700; color: var(--color-text); }
.item-type-badge { font-size: 0.7rem; color: var(--color-text-muted); font-weight: 600; }

.item-right-wrap { display: flex; align-items: center; gap: 12px; }
.item-value { font-family: var(--font-display); font-size: 0.95rem; font-weight: 700; color: var(--color-text); }

.delete-btn {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  padding: 6px;
  cursor: pointer;
  border-radius: 6px;
  box-shadow: none !important;
  opacity: 0.4;
  transition: all 0.2s ease;
}
.delete-btn:hover { opacity: 1; color: var(--color-danger); background: rgba(224, 59, 84, 0.06); }

.settings-empty { font-size: 0.82rem; color: var(--color-text-muted); text-align: center; padding: 1.5rem 0; opacity: 0.7; }

/* Unified Add Modal */
.modal-overlay {
  position: absolute;
  top: 0; left: 0; right: 0; bottom: 0;
  background: var(--color-bg);
  z-index: 2000;
  display: flex;
  flex-direction: column;
  overflow-y: auto;
  -webkit-overflow-scrolling: touch;
}

.modal-navbar {
  display: grid;
  grid-template-columns: 40px 1fr 40px;
  align-items: center;
  width: 100%;
  padding: 16px 18px;
  background: var(--color-bg);
  position: sticky;
  top: 0;
  z-index: 2010;
  box-sizing: border-box;
}

.nav-back-circle {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.05);
  border: none;
  color: var(--color-text);
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  padding: 0 !important;
  box-shadow: none !important;
  transition: background 0.2s ease;
}

.nav-back-circle:hover {
  background: rgba(0, 0, 0, 0.08);
}

.nav-title {
  color: var(--color-text);
  font-size: 1.15rem;
  font-weight: 700;
  text-align: center;
}

.nav-placeholder {
  width: 36px;
  height: 36px;
}

.modal-content-full {
  width: 100%;
  max-width: 600px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  padding: 0 18px 40px 18px;
  box-sizing: border-box;
}

.cat-blocks-stack {
  display: flex;
  flex-direction: column;
  gap: 12px;
  width: 100%;
  margin-top: 8px;
}

.cat-group-wrapper {
  display: flex;
  flex-direction: column;
  width: 100%;
}

.cat-block-btn {
  width: 100%;
  height: 52px;
  border-radius: 16px;
  border: none;
  padding: 0 20px;
  font-size: 1.05rem;
  font-weight: 800;
  text-align: left;
  cursor: pointer;
  display: flex;
  align-items: center;
  transition: all 0.2s ease;
  box-shadow: none !important;
  box-sizing: border-box;
}

.cat-block-btn:hover {
  filter: brightness(1.05);
}

.cat-block-btn:active {
  transform: scale(0.99);
}

/* Category colors matching Percento */
.block-liquid { background-color: #2ebd59 !important; color: #121212 !important; }
.block-invest { background-color: #5c67f5 !important; color: #121212 !important; }
.block-fixed { background-color: #3a59cc !important; color: #121212 !important; }
.block-receivable { background-color: #8ba4e8 !important; color: #121212 !important; }
.block-liab { background-color: #ccd7f5 !important; color: #121212 !important; }

/* Accordion panels */
.accordion-panel {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 8px;
  margin-bottom: 4px;
  overflow: hidden;
  max-height: 300px;
}

.sub-type-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: var(--color-card-bg) !important;
  border: 1px solid var(--color-card-border) !important;
  border-radius: 16px;
  height: 54px;
  padding: 0 20px;
  width: 100%;
  color: var(--color-text);
  cursor: pointer;
  box-shadow: none !important;
  transition: background 0.2s ease;
  box-sizing: border-box;
}

.sub-type-item:hover {
  background: rgba(0, 0, 0, 0.02) !important;
}

.sub-item-left {
  display: flex;
  align-items: center;
  gap: 14px;
}

.sub-icon {
  flex-shrink: 0;
}

.chevron-icon {
  color: rgba(0, 0, 0, 0.3);
}

.text-green { color: #2ebd59 !important; }
.text-purple { color: #8c96f8 !important; }
.text-blue { color: #3a59cc !important; }
.text-light-blue { color: #8ba4e8 !important; }
.text-gray-blue { color: #ccd7f5 !important; }

/* Form fields styling */
.form-body {
  display: flex;
  flex-direction: column;
  gap: 16px;
  margin-top: 12px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
  text-align: left;
}

.form-group label {
  font-size: 0.8rem;
  font-weight: 700;
  color: var(--color-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding-left: 4px;
}

.form-row-group {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

.modal-overlay input:not(.reset-input):not(.input-flat-right),
.modal-overlay select:not(.select-flat-right) {
  background: #f1f5f9 !important;
  border: 1px solid rgba(0, 0, 0, 0.08) !important;
  color: var(--color-text) !important;
  border-radius: 12px !important;
  padding: 12px 14px !important;
  font-size: 0.95rem !important;
  width: 100% !important;
  box-sizing: border-box !important;
  margin-bottom: 0 !important;
  transition: border-color 0.2s ease, box-shadow 0.2s ease !important;
}

.modal-overlay input:not(.reset-input):not(.input-flat-right):focus,
.modal-overlay select:not(.select-flat-right):focus {
  outline: none !important;
  border-color: var(--focused-color, #5c67f5) !important;
  box-shadow: 0 0 0 3px rgba(92, 103, 245, 0.15) !important;
}

.save-error {
  font-size: 0.82rem;
  color: #ff453a;
  background: rgba(255, 69, 58, 0.1);
  border-radius: 8px;
  padding: 10px 14px;
  text-align: left;
  margin-top: 12px;
  border: 1px solid rgba(255, 69, 58, 0.15);
}

.modal-actions {
  display: flex;
  gap: 12px;
  margin-top: 24px;
}

.modal-actions button {
  flex: 1;
  height: 48px;
  font-size: 0.95rem;
  font-weight: 700;
  border-radius: 14px;
  border: none;
  cursor: pointer;
  transition: all 0.2s ease;
  box-shadow: none !important;
  display: flex;
  align-items: center;
  justify-content: center;
}

.btn-cancel {
  background: rgba(0, 0, 0, 0.05) !important;
  color: var(--color-text) !important;
}

.btn-cancel:hover {
  background: rgba(0, 0, 0, 0.08) !important;
}

.btn-save {
  transition: filter 0.2s ease, transform 0.1s ease !important;
}

.btn-save:hover {
  filter: brightness(1.1);
}

.btn-save:active {
  transform: scale(0.98);
}

.empty-state {
  height: 180px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: var(--color-text-muted);
  border: 1px dashed rgba(0, 0, 0, 0.08);
  background: rgba(0, 0, 0, 0.01);
  border-radius: var(--radius-lg);
  padding: 1.5rem;
  text-align: center;
}

.loading-spinner {
  width: 24px;
  height: 24px;
  border: 2px solid rgba(0, 0, 0, 0.05);
  border-top: 2px solid var(--color-primary);
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

/* Transitions */
.accordion-slide-enter-active {
  transition: max-height 0.25s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.25s ease, transform 0.25s ease;
}
.accordion-slide-leave-active {
  transition: max-height 0.2s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.2s ease, transform 0.2s ease;
}
.accordion-slide-enter-from, .accordion-slide-leave-to {
  opacity: 0;
  transform: translateY(-8px);
  max-height: 0;
}

@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}

@keyframes rotate { to { transform: rotate(360deg); } }

/* Toast Notification styling */
.app-toast {
  position: fixed;
  top: 24px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 3000;
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  border: 1px solid rgba(0, 0, 0, 0.06);
  color: var(--color-text);
  padding: 12px 24px;
  border-radius: 50px;
  box-shadow: var(--shadow-lg);
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 0.9rem;
  font-weight: 600;
  max-width: 90%;
  text-align: center;
  animation: slideDown 0.3s cubic-bezier(0.16, 1, 0.3, 1) forwards;
}

@keyframes slideDown {
  from { opacity: 0; transform: translate(-50%, -20px); }
  to { opacity: 1; transform: translate(-50%, 0); }
}

/* Dark Card Form Styles */
.form-card-black {
  background: var(--color-card-bg);
  border: 1px solid var(--color-card-border);
  border-radius: 16px;
  padding: 0 16px;
  display: flex;
  flex-direction: column;
  margin-bottom: 20px;
  box-shadow: var(--shadow-sm);
}

.form-item-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 16px 0;
  border-bottom: 1px solid rgba(0, 0, 0, 0.06);
}

.row-label {
  color: var(--color-text);
  font-size: 0.95rem;
  font-weight: 700;
}

.row-value-wrapper {
  display: flex;
  align-items: center;
  gap: 8px;
}

.input-flat-right {
  background: transparent !important;
  border: none !important;
  color: var(--color-text) !important;
  text-align: right !important;
  font-size: 0.95rem !important;
  width: 200px !important;
  padding: 0 !important;
  margin: 0 !important;
  box-shadow: none !important;
  border-radius: 0 !important;
  height: 24px !important;
  line-height: 24px !important;
}

.select-flat-right {
  background: transparent !important;
  border: none !important;
  color: var(--color-text) !important;
  text-align: right !important;
  font-size: 0.95rem !important;
  width: auto !important;
  padding: 0 20px 0 0 !important;
  box-shadow: none !important;
  outline: none !important;
  appearance: none;
  border-radius: 0 !important;
}

.currency-badge {
  background: rgba(0, 0, 0, 0.05);
  color: var(--color-text);
  padding: 4px 8px;
  border-radius: 20px;
  font-size: 0.76rem;
  font-weight: 800;
}

/* iOS Toggle Switch */
.toggle-switch {
  position: relative;
  display: inline-block;
  width: 48px;
  height: 28px;
}

.toggle-switch input {
  opacity: 0;
  width: 0;
  height: 0;
}

.toggle-slider {
  position: absolute;
  cursor: pointer;
  top: 0; left: 0; right: 0; bottom: 0;
  background-color: #cbd5e1;
  transition: .3s;
  border-radius: 34px;
}

.toggle-slider:before {
  position: absolute;
  content: "";
  height: 22px;
  width: 22px;
  left: 3px;
  bottom: 3px;
  background-color: white;
  transition: .3s;
  border-radius: 50%;
}

.toggle-switch input:checked + .toggle-slider {
  background-color: #2ebd59;
}

.toggle-switch input:checked + .toggle-slider:before {
  transform: translateX(20px);
}

/* Auto-record Dashboard components */
.auto-record-bar-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 8px 4px 16px 4px;
}

.auto-record-left {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--color-text);
  font-size: 0.95rem;
  font-weight: 700;
}

.auto-record-icon {
  color: var(--color-text-muted);
}

.btn-add-auto-record {
  background: transparent;
  border: 1px solid rgba(0, 0, 0, 0.15);
  color: var(--color-text);
  padding: 6px 14px;
  border-radius: 20px;
  font-size: 0.8rem;
  font-weight: 700;
  cursor: pointer;
  transition: all 0.2s ease;
  box-shadow: none !important;
}

.btn-add-auto-record:hover {
  background: rgba(0, 0, 0, 0.02);
  border-color: rgba(0, 0, 0, 0.3);
}

.auto-record-info-badge {
  display: flex;
  align-items: center;
  gap: 12px;
}

.badge-text {
  color: #2ebd59;
  font-size: 0.85rem;
  font-weight: 700;
  cursor: pointer;
}

.badge-text:hover {
  text-decoration: underline;
}

.badge-clear-btn {
  background: transparent;
  border: none;
  color: #ff453a;
  font-size: 0.8rem;
  font-weight: 700;
  cursor: pointer;
  padding: 4px 8px;
  box-shadow: none !important;
}

.badge-clear-btn:hover {
  text-decoration: underline;
}

.auto-record-info-card {
  display: flex;
  gap: 10px;
  background: var(--color-card-bg);
  border: 1px solid var(--color-card-border);
  border-radius: 16px;
  padding: 16px;
  align-items: flex-start;
  box-shadow: var(--shadow-sm);
}

.info-icon {
  color: var(--color-text-muted);
  flex-shrink: 0;
  margin-top: 2px;
}

.info-text {
  color: var(--color-text-muted);
  font-size: 0.8rem;
  line-height: 1.4;
  text-align: left;
}

/* Segmented Control (Tabs) */
.segmented-control {
  display: flex;
  background: rgba(0, 0, 0, 0.04);
  border-radius: 12px;
  padding: 4px;
  width: 100%;
  box-sizing: border-box;
}

.seg-btn {
  flex: 1;
  border: none;
  background: transparent !important;
  color: var(--color-text-muted) !important;
  font-size: 0.82rem;
  font-weight: 700;
  height: 38px;
  border-radius: 9px;
  cursor: pointer;
  transition: all 0.2s ease;
  box-shadow: none !important;
  white-space: nowrap;
  padding: 0 4px !important;
}

.seg-btn.active-income.active {
  background: #2ebd59 !important;
  color: #ffffff !important;
}

.seg-btn.active-expense.active {
  background: #3a59cc !important;
  color: #ffffff !important;
}

.seg-btn.active-transfer.active {
  background: #3a59cc !important;
  color: #ffffff !important;
}

.seg-btn.active-dca_invest.active {
  background: #8b5cf6 !important;
  color: #ffffff !important;
}

.seg-btn.active-invest {
  background: #5c67f5 !important;
  color: #ffffff !important;
}

.seg-btn.active-liquid {
  background: #2ebd59 !important;
  color: #ffffff !important;
}

/* Expiry pill selector */
.expiry-pill-selector {
  display: flex;
  gap: 8px;
}

.expiry-pill {
  border: none;
  border-radius: 8px;
  height: 32px;
  padding: 0 16px !important;
  font-size: 0.85rem !important;
  font-weight: 700 !important;
  cursor: pointer;
  transition: all 0.2s ease;
  box-shadow: none !important;
  background: transparent !important;
  color: var(--color-text) !important;
  border: 1px solid rgba(0, 0, 0, 0.15) !important;
}

.expiry-pill.active {
  background: #e2eeff !important;
  color: #0056d6 !important;
  border: 1px solid #e2eeff !important;
}

/* Minus circle button style */
.minus-circle-btn {
  background: transparent;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: color 0.2s ease;
  box-shadow: none !important;
}

.minus-circle-btn:hover {
  color: var(--color-text);
}

/* Invisible select overlay style */
.invisible-select {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  opacity: 0;
  cursor: pointer;
  z-index: 2;
}

/* Label grouping for amount */
.row-label-group {
  display: flex;
  flex-direction: column;
  text-align: left;
}

.row-sublabel {
  font-size: 0.72rem;
  color: var(--color-text-muted);
  font-weight: 500;
  margin-top: 2px;
}

/* Date and Tag styles */
.next-time-hint {
  font-size: 0.8rem;
  color: var(--color-text-muted);
  text-align: right;
  margin-top: -8px;
  margin-bottom: 8px;
  padding-right: 8px;
}

.red-placeholder::placeholder {
  color: #ff453a !important;
}

.red-text {
  color: #ff453a !important;
  font-weight: 700;
}

/* Header and Navbar layout */
.provider-type-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 6px;
  margin-bottom: 8px;
}

.row-label-gray {
  color: var(--color-text-muted);
  font-size: 0.95rem;
  font-weight: 700;
}

.provider-type-right {
  display: flex;
  align-items: center;
  gap: 8px;
}

.provider-type-text {
  color: var(--color-text);
  font-size: 0.95rem;
  font-weight: 700;
}

.nav-save-circle {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.05);
  border: none;
  color: #2ebd59;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  padding: 0 !important;
  box-shadow: none !important;
  transition: background 0.2s ease;
}

.nav-save-circle:hover {
  background: rgba(0, 0, 0, 0.08);
}

.mini-spinner {
  width: 16px;
  height: 16px;
  border: 2px solid rgba(0, 0, 0, 0.05);
  border-top: 2px solid #2ebd59;
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

.caret-indicator {
  color: var(--color-text-muted);
  transition: transform 0.2s ease;
}
.caret-indicator-white {
  color: var(--color-text);
  transition: transform 0.2s ease;
}

.list-sub-item-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 14px 18px !important;
  background: #ffffff !important;
  border-radius: 20px !important;
  box-shadow: 0 4px 15px rgba(0, 0, 0, 0.02) !important;
  border: 1px solid rgba(0, 0, 0, 0.01) !important;
  margin-bottom: 10px !important;
  transition: transform 0.2s ease, box-shadow 0.2s ease;
}

.list-sub-item-card:hover {
  transform: translateY(-2px);
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.04) !important;
}

.list-sub-item-card .sub-item-name {
  font-size: 1.05rem;
}
.list-sub-item-card .sub-item-val {
  font-size: 1.15rem;
}

.sub-item-right-val {
  display: flex;
  align-items: center;
  gap: 4px;
}

/* Treemap styling matching the screenshot */
.treemap-container {
  display: flex;
  gap: 12px;
  height: calc(100vh - 200px);
  width: 100%;
  margin-top: 16px;
  box-sizing: border-box;
}

.treemap-column {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.treemap-left {
  width: 30%;
}

.treemap-right {
  width: 70%;
  gap: 4px;
}

.treemap-full {
  width: 100%;
  gap: 4px;
}

.treemap-spacer {
  transition: flex 0.3s ease;
}

.treemap-block {
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  padding: 12px 16px;
  box-sizing: border-box;
  border-radius: 20px;
  transition: flex 0.3s ease;
  text-align: left;
  overflow: hidden;
  min-height: 60px; /* Prevent text clipping */
}

.block-pct {
  font-size: 1.8rem;
  font-weight: 800;
  font-family: var(--font-display);
  line-height: 1.1;
}

.block-name {
  font-size: 0.85rem;
  font-weight: 700;
  margin-top: 2px;
  opacity: 0.9;
}

.block-liab-val {
  background-color: #ccd7f5;
  color: #121212;
}

.block-invest-val {
  background-color: #5c67f5;
  color: #ffffff;
}

.block-liquid-val {
  background-color: #5ebd74;
  color: #ffffff;
}

.block-fixed-val {
  background-color: #3a59cc;
  color: #ffffff;
}

.block-receivable-val {
  background-color: #8ba4e8;
  color: #121212;
}

/* Tab Fade Slide Transition */
.fade-tab-enter-active,
.fade-tab-leave-active {
  transition: opacity 0.2s cubic-bezier(0.4, 0, 0.2, 1), transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}
.fade-tab-enter-from {
  opacity: 0;
  transform: translateY(8px);
}
.fade-tab-leave-to {
  opacity: 0;
  transform: translateY(-8px);
}

/* Smooth Collapsible Height Transition using CSS Grid */
.collapsible-wrapper {
  display: grid;
  grid-template-rows: 0fr;
  transition: margin-top 0.3s ease, grid-template-rows 0.35s cubic-bezier(0.32, 0.94, 0.6, 1);
  overflow: hidden;
  margin-top: 0;
}
.collapsible-wrapper.expanded {
  grid-template-rows: 1fr;
  margin-top: 12px;
}
.collapsible-content {
  min-height: 0;
  opacity: 0;
  transform: translateY(-12px) scale(0.98);
  transition: opacity 0.3s ease, transform 0.35s cubic-bezier(0.32, 0.94, 0.6, 1);
  transform-origin: top center;
}
.collapsible-wrapper.expanded .collapsible-content {
  opacity: 1;
  transform: translateY(0) scale(1);
}

/* Modal Slide Transition (iOS style slide-up from bottom) */
.modal-slide-enter-active,
.modal-slide-leave-active {
  transition: opacity 0.33s cubic-bezier(0.32, 0.94, 0.6, 1), transform 0.33s cubic-bezier(0.32, 0.94, 0.6, 1);
}
.modal-slide-enter-from,
.modal-slide-leave-to {
  opacity: 0;
  transform: translateY(100%);
}

/* Layout inline for small percentage blocks in treemap */
.treemap-block.layout-inline {
  flex-direction: row !important;
  justify-content: flex-start !important;
  align-items: center !important;
  gap: 8px !important;
  padding: 6px 16px !important;
}
.treemap-block.layout-inline .block-pct {
  font-size: 1.3rem !important;
}
.treemap-block.layout-inline .block-name {
  margin-top: 0 !important;
  font-size: 0.8rem !important;
  opacity: 0.85 !important;
}
.text-white {
  color: #ffffff !important;
}
.text-dark {
  color: #1a1a1a !important;
}
</style>