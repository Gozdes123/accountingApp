<script setup>
import { ref, onMounted, onActivated, computed } from 'vue'
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
  const months = ['1月', '2月', '3月', '4月', '5月', '6月']
  
  if (statsType.value === 'invest') {
    const totalPnL = investments.value.reduce((sum, item) => {
      const qty = Number(item.quantity || 0)
      const current = Number(item.current_price || 0)
      const cost = Number(item.buy_price || item.average_cost || 0)
      const raw = qty * (current - cost)
      const currency = item.currency || 'TWD'
      return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
    }, 0)
    
    const currentInvestVal = totalInvestments.value
    const accountChangeData = [0, 0, 0, 0, 0, currentInvestVal > 0 ? 10730 : 0]
    const pnlData = [0, 0, 0, 0, 0, totalPnL]
    
    return {
      labels: months,
      datasets: [
        {
          label: '帳戶改變',
          backgroundColor: '#ccd7f5',
          borderRadius: 8,
          data: accountChangeData
        },
        {
          label: '持倉盈虧',
          backgroundColor: '#5c67f5',
          borderRadius: 8,
          data: pnlData
        }
      ]
    }
  } else {
    let monthlyIncome = 0
    let monthlyExpense = 0
    accounts.value.forEach(acc => {
      if (acc.auto_record && acc.auto_record.enabled) {
        if (acc.auto_record.type === 'income') {
          monthlyIncome += Number(acc.auto_record.amount || 0)
        } else if (acc.auto_record.type === 'expense') {
          monthlyExpense += Number(acc.auto_record.amount || 0)
        }
      }
    })
    
    const finalIncome = monthlyIncome || (totalLiquidAssets.value > 0 ? 1000000 : 0)
    const finalExpense = monthlyExpense || 0
    
    const incomeData = [0, 0, 0, 0, 0, finalIncome]
    const expenseData = [0, 0, 0, 0, 0, finalExpense]
    
    return {
      labels: months,
      datasets: [
        {
          label: '收入',
          backgroundColor: '#2ebd59',
          borderRadius: 8,
          data: incomeData
        },
        {
          label: '支出',
          backgroundColor: '#d1d5db',
          borderRadius: 8,
          data: expenseData
        }
      ]
    }
  }
})

const statsSummaryText = computed(() => {
  if (statsType.value === 'invest') {
    const totalPnL = investments.value.reduce((sum, item) => {
      const qty = Number(item.quantity || 0)
      const current = Number(item.current_price || 0)
      const cost = Number(item.buy_price || item.average_cost || 0)
      const raw = qty * (current - cost)
      const currency = item.currency || 'TWD'
      return sum + (currency === 'USD' ? raw * usdTwdRate.value : raw)
    }, 0)
    const currentInvestVal = totalInvestments.value
    const accountChange = currentInvestVal > 0 ? 10730 : 0
    
    return {
      title: '2026年1月至6月',
      desc1: `帳戶改變總計 ${formatInvestNumber(accountChange)} 元，`,
      desc2: totalPnL === 0 ? '持倉盈虧沒有改變' : `持倉盈虧${totalPnL > 0 ? '增加' : '減少'}了 ${formatInvestNumber(Math.abs(totalPnL))} 元`
    }
  } else {
    let monthlyIncome = 0
    let monthlyExpense = 0
    accounts.value.forEach(acc => {
      if (acc.auto_record && acc.auto_record.enabled) {
        if (acc.auto_record.type === 'income') {
          monthlyIncome += Number(acc.auto_record.amount || 0)
        } else if (acc.auto_record.type === 'expense') {
          monthlyExpense += Number(acc.auto_record.amount || 0)
        }
      }
    })
    const finalIncome = monthlyIncome || (totalLiquidAssets.value > 0 ? 1000000 : 0)
    const finalExpense = monthlyExpense || 0
    
    return {
      title: '2026年1月至6月',
      desc1: `收入總計 ${formatInvestNumber(finalIncome)} 元，`,
      desc2: finalExpense === 0 ? '支出沒有改變' : `支出總計 ${formatInvestNumber(finalExpense)} 元`
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
const isInitialDataLoaded = ref(false)
const isHidden = ref(true)
const isRefreshing = ref(false)

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
  
  newAsset.value = {
    category: getCategoryFromType(acc.type),
    type: acc.type,
    name: acc.name,
    balance: acc.balance,
    include_in_chart: acc.include_in_chart ?? true,
    remarks: acc.remarks ?? '',
    auto_record: acc.auto_record ? JSON.parse(JSON.stringify(acc.auto_record)) : null,
    custom_group: acc.custom_group ?? '',
    funding_account_id: null
  }
  
  subListType.value = null
  showAddModal.value = true
  addModalStep.value = 2
}

const editInvestment = (inv) => {
  isEditing.value = true
  editingId.value = inv.id
  
  newAsset.value = {
    category: 'invest',
    type: inv.asset_class || inv.type || 'Stock',
    name: inv.name || '',
    symbol: inv.symbol || '',
    quantity: inv.quantity || 0,
    buy_price: inv.average_cost || inv.buy_price || 0,
    buy_date: inv.buy_date || new Date().toISOString().split('T')[0],
    custom_group: inv.custom_group ?? '',
    funding_account_id: inv.funding_account_id || null
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

const handleTagInput = (e) => {
  let val = e.target.value
  if (val && !val.startsWith('#')) {
    newAsset.value.auto_record.tag = '#' + val
  } else {
    newAsset.value.auto_record.tag = val
  }
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

const initAutoRecord = () => {
  autoRecordBackup.value = newAsset.value.auto_record ? JSON.parse(JSON.stringify(newAsset.value.auto_record)) : null
  newAsset.value.auto_record = {
    enabled: true, 
    type: 'expense',
    amount: 0,
    day: 1,
    tag: '',
    expiry: 'forever',
    last_processed_date: null
  }
  addModalStep.value = 3
}

const enterAutoRecordConfig = () => {
  autoRecordBackup.value = newAsset.value.auto_record ? JSON.parse(JSON.stringify(newAsset.value.auto_record)) : null
  addModalStep.value = 3
}

const cancelAutoRecordConfig = () => {
  newAsset.value.auto_record = autoRecordBackup.value
  addModalStep.value = 2
}

const nextRecordDateStr = computed(() => {
  if (!newAsset.value.auto_record) return ''
  const today = new Date()
  let targetMonth = today.getMonth()
  let targetYear = today.getFullYear()
  const day = Number(newAsset.value.auto_record.day || 1)
  
  if (today.getDate() >= day) {
    targetMonth++
    if (targetMonth > 11) {
      targetMonth = 0
      targetYear++
    }
  }
  return `${targetMonth + 1}月${day}日`
})

// 新增項目 Modal
const showAddModal = ref(false)
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
    if (finalQtyChange > 0) {
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
        price_updated_at: nowStr
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
      for (let i = 0; i < lots.length; i++) {
        const lot = lots[i]
        if (lot.quantity >= remainingToSubtract) {
          lot.quantity -= remainingToSubtract
          remainingToSubtract = 0
          try {
            await supabase.from('investments').update({ quantity: lot.quantity }).eq('id', lot.id)
          } catch {}
          break;
        } else {
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
  }
  
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
    
    // Adjust cash account if linked
    if (firstLot.funding_account_id) {
      const oldCost = oldQty * oldPrice
      const oldCostTwd = firstLot.currency === 'USD' ? oldCost * usdTwdRate.value : oldCost
      
      const newCost = newQty * buyPrice
      const newCostTwd = firstLot.currency === 'USD' ? newCost * usdTwdRate.value : newCost
      
      const diffTwd = newCostTwd - oldCostTwd
      
      accounts.value = accounts.value.map(acc => {
        if (acc.id === firstLot.funding_account_id) {
          acc.balance -= diffTwd
          if (acc.balance < 0) acc.balance = 0
          try {
            supabase.from('accounts').update({ balance: acc.balance }).eq('id', acc.id)
          } catch (dbErr) {
            console.warn('Sync account balance after inline modification failed:', dbErr)
          }
        }
        return acc
      })
      localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
    }
    
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
    .reduce((sum, acc) => sum + Math.abs(Number(acc.balance)), 0)
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
    .reduce((sum, acc) => sum + Math.abs(Number(acc.balance)), 0)
})

// 4. 應收款項目 (Receivable)
const totalReceivables = computed(() => {
  return accounts.value
    .filter(a => a.type === 'Receivable' && a.include_in_chart !== false)
    .reduce((sum, acc) => sum + Math.abs(Number(acc.balance)), 0)
})

// 5. 負債項目 (Liability / Credit Card / Loan / Payable / OtherLiab)
const totalLiabilities = computed(() => {
  const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
  return accounts.value
    .filter(a => liabTypes.includes(a.type) && a.include_in_chart !== false)
    .reduce((sum, acc) => sum + Math.abs(Number(acc.balance)), 0)
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
        price_updated_at: inv.price_updated_at,
        custom_group: inv.custom_group || ''
      }
    }
    groups[sym].qty += Number(inv.quantity || 0)
    if (inv.price_updated_at && (!groups[sym].price_updated_at || inv.price_updated_at > groups[sym].price_updated_at)) {
      groups[sym].price_updated_at = inv.price_updated_at
      groups[sym].current_price = Number(inv.current_price || 0)
    }
  })

  return Object.values(groups).map(g => {
    const rawVal = g.qty * g.current_price
    const valTwd = g.currency === 'USD' ? rawVal * usdTwdRate.value : rawVal
    const pct = totalInvestments.value > 0 ? (valTwd / totalInvestments.value) * 100 : 0
    return {
      ...g,
      valueTwd: valTwd,
      percentage: pct
    }
  }).sort((a, b) => b.valueTwd - a.valueTwd)
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
      result.push({
        isGroup: true,
        name: g.name,
        percentage: g.percentage,
        valueTwd: g.totalValueTwd,
        items: g.items,
        desc: g.items.map(i => i.name || i.symbol).join('、'),
        price_updated_at: g.items[0]?.price_updated_at
      })
    } else {
      g.items.forEach(item => {
        const itemPct = totalInvestments.value > 0 ? (item.valueTwd / totalInvestments.value) * 100 : 0
        result.push({
          isGroup: false,
          name: item.name,
          symbol: item.symbol,
          percentage: itemPct,
          valueTwd: item.valueTwd,
          desc: `持有 ${item.qty}, ${item.currency} ${item.current_price}`,
          price_updated_at: item.price_updated_at,
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

const getCategoryFlatList = (category) => {
  const result = []
  const grouped = groupAccountsByCustomGroup(category)
  const catTotal = getCategoryTotal(category)
  
  grouped.forEach(g => {
    if (g.name !== '') {
      const groupTotal = g.items.reduce((sum, item) => sum + item.balance, 0)
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
        const itemPct = catTotal > 0 ? (item.balance / catTotal) * 100 : 0
        result.push({
          isGroup: false,
          name: item.name,
          category,
          percentage: itemPct,
          balance: item.balance,
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

// 雙模式走勢數據計算 (結合當前實際比例與歷史淨值)
const trendDatasets = computed(() => {
  const history = filteredHistory.value
  if (history.length === 0) return []
  
  const todayNetWorth = netWorth.value
  const todayLiabilities = totalLiabilities.value
  const todayLiquid = totalLiquidAssets.value
  const todayInvest = totalInvestments.value
  
  const totalAssets = todayNetWorth + todayLiabilities
  const liabRatio = totalAssets > 0 ? todayLiabilities / totalAssets : 0
  const nwRatio = totalAssets > 0 ? todayNetWorth / totalAssets : 1
  
  const totalPos = todayLiquid + todayInvest
  const liquidRatio = totalPos > 0 ? todayLiquid / totalPos : 0.5
  const investRatio = totalPos > 0 ? todayInvest / totalPos : 0.5
  
  return history.map((r, idx) => {
    // 預估歷史節點數值，最後一個節點強制符合當前真實數據
    if (idx === history.length - 1) {
      return {
        date: r.date,
        netWorth: todayNetWorth,
        liabilities: todayLiabilities,
        liquid: todayLiquid,
        invest: todayInvest
      }
    }
    
    // 計算該歷史節點的資產總值與正資產總值
    const estTotalAssets = r.amount / (nwRatio || 1)
    const estLiabilities = Math.abs(estTotalAssets * liabRatio)
    
    const estTotalPos = r.amount + estLiabilities
    const estLiquid = estTotalPos * liquidRatio
    const estInvest = estTotalPos * investRatio
    
    return {
      date: r.date,
      netWorth: r.amount,
      liabilities: estLiabilities,
      liquid: estLiquid,
      invest: estInvest
    }
  })
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
  if (datasets.length < 2) return { nw: '我的淨資產沒有改變', liab: '我的負債沒有改變' }
  
  const first = datasets[0]
  const last = datasets[datasets.length - 1]
  
  const nwDiff = last.netWorth - first.netWorth
  const nwPct = first.netWorth !== 0 ? Math.round((nwDiff / Math.abs(first.netWorth)) * 100) : (nwDiff !== 0 ? 100 : 0)
  const nwDirection = nwDiff >= 0 ? '增加' : '減少'
  const nwText = `我的淨資產${nwDirection}了 ${formatInvestNumber(Math.abs(nwDiff))} 元，較期初 ${nwPct >= 0 ? '+' : ''}${nwPct}%`
  
  const liabDiff = last.liabilities - first.liabilities
  const liabPct = first.liabilities !== 0 ? Math.round((liabDiff / Math.abs(first.liabilities)) * 100) : (liabDiff !== 0 ? 100 : 0)
  const liabDirection = liabDiff >= 0 ? '增加' : '減少'
  const liabText = liabDiff === 0 ? '我的負債沒有改變' : `我的負債${liabDirection}了 ${formatInvestNumber(Math.abs(liabDiff))} 元，較期初 ${liabPct >= 0 ? '+' : ''}${liabPct}%`
  
  return { nw: nwText, liab: liabText }
})

const liquidInvestSummaryText = computed(() => {
  const datasets = trendDatasets.value
  if (datasets.length < 2) return { liquid: '我的流動資金沒有改變', invest: '我的投資沒有改變' }
  
  const first = datasets[0]
  const last = datasets[datasets.length - 1]
  
  const liqDiff = last.liquid - first.liquid
  const liqPct = first.liquid !== 0 ? Math.round((liqDiff / Math.abs(first.liquid)) * 100) : (liqDiff !== 0 ? 100 : 0)
  const liqDirection = liqDiff >= 0 ? '增加' : '減少'
  const liqText = liqDiff === 0 ? '我的流動資金沒有改變' : `我的流動資金${liqDirection}了 ${formatInvestNumber(Math.abs(liqDiff))} 元，較期初 ${liqPct >= 0 ? '+' : ''}${liqPct}%`
  
  const invDiff = last.invest - first.invest
  const invPct = first.invest !== 0 ? Math.round((invDiff / Math.abs(first.invest)) * 100) : (invDiff !== 0 ? 100 : 0)
  const invDirection = invDiff >= 0 ? '增加' : '減少'
  const invText = invDiff === 0 ? '我的投資沒有改變' : `我的投資${invDirection}了 ${formatInvestNumber(Math.abs(invDiff))} 元，較期初 ${invPct >= 0 ? '+' : ''}${invPct}%`
  
  return { liquid: liqText, invest: invText }
})

const trendChartData = computed(() => {
  const datasets = trendDatasets.value
  const labels = datasets.map(r => {
    const d = new Date(r.date)
    return `${d.getMonth() + 1}月`
  })
  
  if (trendType.value === 'net_worth') {
    const nwData = datasets.map(r => r.netWorth)
    const liabData = datasets.map(r => r.liabilities)
    return {
      labels,
      datasets: [
        {
          data: nwData,
          borderColor: '#5c67f5',
          tension: 0.35,
          borderWidth: 2.5,
          fill: false,
          pointRadius: datasets.length > 20 ? 0 : 2,
          pointHoverRadius: 5
        },
        {
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
  } else {
    const liquidData = datasets.map(r => r.liquid)
    const investData = datasets.map(r => r.invest)
    return {
      labels,
      datasets: [
        {
          data: liquidData,
          borderColor: '#2ec173',
          tension: 0.35,
          borderWidth: 2.5,
          fill: false,
          pointRadius: datasets.length > 20 ? 0 : 2,
          pointHoverRadius: 5
        },
        {
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
  }
})

const trendChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
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
      cornerRadius: 8
    }
  },
  scales: {
    y: {
      grid: { color: 'rgba(255, 255, 255, 0.05)' },
      ticks: { 
        color: 'rgba(255, 255, 255, 0.4)', 
        font: { size: 10, family: 'Inter' },
        callback: (value) => {
          if (Math.abs(value) >= 1000000) {
            return (value / 1000000) + 'm';
          }
          if (Math.abs(value) >= 1000) {
            return (value / 1000) + 'k';
          }
          return value;
        }
      }
    },
    x: {
      grid: { display: false },
      ticks: { color: 'rgba(255, 255, 255, 0.4)', font: { size: 10, family: 'Inter' }, maxTicksLimit: 8 }
    }
  }
}

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

const fetchAllData = async () => {
  // 1. 快取優先渲染 (SWR) — 如果本機有舊資料，直接先呈現在畫面上，達成秒開效果
  const cachedAccs = localStorage.getItem('local_accounts')
  const cachedInvs = localStorage.getItem('local_investments')
  const cachedRate = localStorage.getItem('cached_usd_twd_rate')
  
  if (cachedAccs || cachedInvs) {
    if (cachedAccs) accounts.value = JSON.parse(cachedAccs)
    if (cachedInvs) investments.value = JSON.parse(cachedInvs)
    if (cachedRate) usdTwdRate.value = Number(cachedRate)
    isInitialDataLoaded.value = true
  }

  // 2. 背景抓取即時匯率
  try {
    const res = await fetch('https://api.exchangerate-api.com/v4/latest/USD')
    const rateData = await res.json()
    usdTwdRate.value = rateData.rates?.TWD ?? 32
    localStorage.setItem('cached_usd_twd_rate', usdTwdRate.value.toString())
  } catch {
    if (!cachedRate) usdTwdRate.value = 32
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
    
    if (!accsErr && accs && accs.length > 0) {
      loadedAccounts = accs
      localStorage.setItem('local_accounts', JSON.stringify(accs))
    } else {
      loadedAccounts = JSON.parse(localStorage.getItem('local_accounts') || '[]')
    }
  } catch (err) {
    console.warn('Supabase accounts query failed, loading locally:', err)
    loadedAccounts = JSON.parse(localStorage.getItem('local_accounts') || '[]')
  }
  
  accounts.value = loadedAccounts

  // 4. 背景獲取最新投資資料 (Supabase)
  let loadedInvestments = []
  try {
    const { data: invs, error: invsErr } = await supabase
      .from('investments')
      .select('*')
      .order('created_at', { ascending: false })
      
    if (!invsErr && invs && invs.length > 0) {
      loadedInvestments = invs
      localStorage.setItem('local_investments', JSON.stringify(invs))
    } else {
      loadedInvestments = JSON.parse(localStorage.getItem('local_investments') || '[]')
    }
  } catch (err) {
    console.warn('Supabase investments query failed, loading locally:', err)
    loadedInvestments = JSON.parse(localStorage.getItem('local_investments') || '[]')
  }
  
  investments.value = loadedInvestments

  // 所有最新資料同步完成後，確保關閉載入畫面
  isInitialDataLoaded.value = true

  // 5. 處理自動記帳 / 自動轉帳
  await processAutoRecords()

  // 6. 儲存每日資產快照
  await saveDailySnapshot(netWorth.value)

  // 6. Sync groups list
  syncGroups()
}

const saveDailySnapshot = async (amount) => {
  const d = new Date()
  const offset = d.getTimezoneOffset()
  const localDate = new Date(d.getTime() - (offset * 60 * 1000))
  const dateStr = localDate.toISOString().split('T')[0]
  
  try {
    const { error } = await supabase
      .from('net_worth_history')
      .upsert({ date: dateStr, amount }, { onConflict: 'date' })
    if (error) saveSnapshotToLocal(dateStr, amount)
  } catch {
    saveSnapshotToLocal(dateStr, amount)
  }
  
  await fetchHistoricalSnapshots()
}

const saveSnapshotToLocal = (dateStr, amount) => {
  let history = JSON.parse(localStorage.getItem('net_worth_history') || '[]')
  const index = history.findIndex(h => h.date === dateStr)
  if (index !== -1) history[index].amount = amount
  else history.push({ date: dateStr, amount })
  history.sort((a, b) => new Date(a.date) - new Date(b.date))
  localStorage.setItem('net_worth_history', JSON.stringify(history))
}

const fetchHistoricalSnapshots = async () => {
  let dbRecords = []
  try {
    const { data, error } = await supabase
      .from('net_worth_history')
      .select('date, amount')
      .order('date', { ascending: true })
    if (!error && data) dbRecords = data
  } catch {}

  const localRecords = JSON.parse(localStorage.getItem('net_worth_history') || '[]')
  const merged = {}
  localRecords.forEach(r => merged[r.date] = Number(r.amount))
  dbRecords.forEach(r => merged[r.date] = Number(r.amount))

  historyRecords.value = Object.entries(merged).map(([date, amount]) => ({
    date,
    amount
  })).sort((a, b) => new Date(a.date) - new Date(b.date))

  // 生成模擬成長曲線
  if (historyRecords.value.length <= 1) {
    const today = new Date()
    const mockData = []
    for (let i = 5; i >= 0; i--) {
      const d = new Date(today.getFullYear(), today.getMonth() - i, today.getDate())
      const dateStr = d.toISOString().split('T')[0]
      const factor = 1 - (i * 0.05)
      mockData.push({
        date: dateStr,
        amount: Math.round(netWorth.value * factor)
      })
    }
    historyRecords.value = mockData
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
    const url = isProd 
      ? `https://api.allorigins.win/raw?url=${encodeURIComponent(yhUrl)}` 
      : `/yahoo-finance/v8/finance/chart/${symbol}?interval=1d&range=1d`
      
    const res = await fetch(url)
    if (!res.ok) return null
    const data = await res.json()
    return data?.chart?.result?.[0]?.meta?.regularMarketPrice ?? null
  } catch {
    return null
  }
}

const refreshPrices = async () => {
  if (isRefreshing.value) return
  isRefreshing.value = true
  
  let count = 0
  const symbolMap = {}
  investments.value.forEach(inv => {
    const key = inv.symbol.toUpperCase()
    if (!symbolMap[key]) symbolMap[key] = { cls: inv.asset_class, ids: [] }
    symbolMap[key].ids.push(inv.id)
  })

  for (const [sym, info] of Object.entries(symbolMap)) {
    const querySym = getYahooSymbol(sym, info.cls)
    const price = await fetchYahooPrice(querySym)
    if (price !== null) {
      const now = new Date().toISOString()
      for (const id of info.ids) {
        try {
          await supabase
            .from('investments')
            .update({ current_price: price, price_updated_at: now })
            .eq('id', id)
        } catch {}
        
        const item = investments.value.find(i => i.id === id)
        if (item) { item.current_price = price; item.price_updated_at = now }
      }
      count++
    }
  }
  
  localStorage.setItem('local_investments', JSON.stringify(investments.value))
  isRefreshing.value = false
  await saveDailySnapshot(netWorth.value)
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
      
      const payload = {
        id: isEditing.value ? editingId.value : generatedId,
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
        custom_group: newAsset.value.custom_group || '',
        funding_account_id: newAsset.value.funding_account_id || null
      }
      
      // Calculate cash funding account adjustment
      const oldInv = isEditing.value ? investments.value.find(i => i.id === editingId.value) : null
      const oldCost = oldInv ? (Number(oldInv.quantity || 0) * Number(oldInv.buy_price || oldInv.average_cost || 0)) : 0
      const oldCostTwd = oldInv && oldInv.currency === 'USD' ? oldCost * usdTwdRate.value : oldCost
      
      const newCost = payload.quantity * payload.buy_price
      const newCostTwd = payload.currency === 'USD' ? newCost * usdTwdRate.value : newCost
      
      const oldFundingId = oldInv ? oldInv.funding_account_id : null
      const newFundingId = payload.funding_account_id
      
      let accountsChanged = false
      const updatedAccounts = [...accounts.value]
      
      if (oldFundingId === newFundingId) {
        if (newFundingId) {
          const acc = updatedAccounts.find(a => a.id === newFundingId)
          if (acc) {
            const diffTwd = newCostTwd - oldCostTwd
            acc.balance -= diffTwd
            if (acc.balance < 0) acc.balance = 0
            acc._dirty = true
            accountsChanged = true
          }
        }
      } else {
        if (oldFundingId) {
          const oldAcc = updatedAccounts.find(a => a.id === oldFundingId)
          if (oldAcc) {
            oldAcc.balance += oldCostTwd
            oldAcc._dirty = true
            accountsChanged = true
          }
        }
        if (newFundingId) {
          const newAcc = updatedAccounts.find(a => a.id === newFundingId)
          if (newAcc) {
            newAcc.balance -= newCostTwd
            if (newAcc.balance < 0) newAcc.balance = 0
            newAcc._dirty = true
            accountsChanged = true
          }
        }
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
        try {
          const dbPayload = { ...payload }
          delete dbPayload.id
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
      
      const payload = {
        id: isEditing.value ? editingId.value : generatedId,
        name: newAsset.value.name,
        type: newAsset.value.type,
        balance: Math.abs(Number(newAsset.value.balance)),
        include_in_chart: newAsset.value.include_in_chart ?? true,
        remarks: newAsset.value.remarks ?? '',
        auto_record: newAsset.value.auto_record ? JSON.parse(JSON.stringify(newAsset.value.auto_record)) : null,
        created_at: isEditing.value ? (accounts.value.find(a => a.id === editingId.value)?.created_at || nowStr) : nowStr,
        custom_group: newAsset.value.custom_group || ''
      }
      
      const dbPayload = {
        name: payload.name,
        type: payload.type,
        balance: payload.balance,
        custom_group: payload.custom_group
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
  triggerDeleteConfirm('確定要刪除此投資項目？此動作將退回買入成本至連結的扣款帳戶。', async () => {
    const inv = investments.value.find(i => i.id === id)
    
    if (id && !String(id).startsWith('local-') && !String(id).startsWith('mock-')) {
      try {
        const { error } = await supabase.from('investments').delete().eq('id', id)
        if (error) console.warn('Supabase delete investment failed:', error)
      } catch (e) {
        console.warn('Supabase delete investment exception:', e)
      }
    }
    
    // Refund linked funding account
    if (inv && inv.funding_account_id) {
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
      localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
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
    if (acc.auto_record && acc.auto_record.enabled) {
      const ar = acc.auto_record
      const day = Number(ar.day || 1)
      
      let lastProcessedYear = 0
      let lastProcessedMonth = -1
      
      if (ar.last_processed_date) {
        const lpd = new Date(ar.last_processed_date)
        lastProcessedYear = lpd.getFullYear()
        lastProcessedMonth = lpd.getMonth()
      }
      
      const isCurrentMonthProcessed = (lastProcessedYear === currentYear && lastProcessedMonth === currentMonth)
      
      if (currentDay >= day && !isCurrentMonthProcessed) {
        const amount = Number(ar.amount || 0)
        const type = ar.type
        
        if (type === 'income') {
          acc.balance += amount
          showToast(`自動記帳：${acc.name} 固定收入 TWD ${amount}`)
        } else if (type === 'expense') {
          acc.balance -= amount
          if (acc.balance < 0) acc.balance = 0
          showToast(`自動記帳：${acc.name} 固定支出 TWD ${amount}`)
        } else if (type === 'transfer') {
          const targetAcc = updatedAccounts.find(a => a.id === ar.target_account_id)
          if (targetAcc) {
            acc.balance -= amount
            if (acc.balance < 0) acc.balance = 0
            
            // 如果轉入的目標帳戶是負債類（如：房貸、信貸、信用卡），轉帳代表還款，應減少負債餘額
            const liabTypes = ['Credit Card', 'Liability', 'Loan', 'Payable', 'OtherLiab']
            if (liabTypes.includes(targetAcc.type)) {
              targetAcc.balance -= amount
              if (targetAcc.balance < 0) targetAcc.balance = 0
            } else {
              targetAcc.balance += amount
            }
            
            targetAcc._dirty = true
            showToast(`自動轉帳：從 ${acc.name} 轉帳至 ${targetAcc.name} TWD ${amount}`)
          } else {
            console.warn(`Target account ${ar.target_account_id} not found for transfer`)
          }
        }
        
        ar.last_processed_date = today.toISOString()
        acc._dirty = true
        changed = true
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
const selectedItemToAddToGroup = ref('')

const manageGroup = (groupName, type) => {
  activeGroupType.value = type
  selectedGroupToManage.value = groupName
  selectedItemToAddToGroup.value = ''
  showManageGroupModal.value = true
}

const getAvailableItemsForGroup = computed(() => {
  if (activeGroupType.value === 'account') {
    return (accounts.value || []).filter(a => a.custom_group !== selectedGroupToManage.value).map(a => ({ id: a.id, name: `🏦 ${a.name} (${translateTypeSettings(a.type)})`, type: 'account' }))
  } else {
    return (investments.value || []).filter(i => i.custom_group !== selectedGroupToManage.value).map(i => ({ id: i.id, name: `📈 ${i.symbol} (${i.name || ''})`, type: 'investment' }))
  }
})

const addItemToGroup = async () => {
  if (!selectedItemToAddToGroup.value) return
  const itemJson = JSON.parse(selectedItemToAddToGroup.value)
  const { id, type } = itemJson

  if (type === 'account') {
    accounts.value = accounts.value.map(a => {
      if (a.id === id) {
        a.custom_group = selectedGroupToManage.value
        if (a.id && !String(a.id).startsWith('local-') && !String(a.id).startsWith('mock-')) {
          supabase.from('accounts').update({ custom_group: selectedGroupToManage.value }).eq('id', a.id)
        }
      }
      return a
    })
    localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
  } else {
    investments.value = investments.value.map(i => {
      if (i.id === id) {
        i.custom_group = selectedGroupToManage.value
        if (i.id && !String(i.id).startsWith('local-') && !String(i.id).startsWith('mock-')) {
          supabase.from('investments').update({ custom_group: selectedGroupToManage.value }).eq('id', i.id)
        }
      }
      return i
    })
    localStorage.setItem('local_investments', JSON.stringify(investments.value))
  }
  selectedItemToAddToGroup.value = ''
}

const removeItemFromGroup = async (id, type) => {
  if (type === 'account') {
    accounts.value = accounts.value.map(a => {
      if (a.id === id) {
        a.custom_group = ''
        if (a.id && !String(a.id).startsWith('local-') && !String(a.id).startsWith('mock-')) {
          supabase.from('accounts').update({ custom_group: '' }).eq('id', a.id)
        }
      }
      return a
    })
    localStorage.setItem('local_accounts', JSON.stringify(accounts.value))
  } else {
    investments.value = investments.value.map(i => {
      if (i.id === id) {
        i.custom_group = ''
        if (i.id && !String(i.id).startsWith('local-') && !String(i.id).startsWith('mock-')) {
          supabase.from('investments').update({ custom_group: '' }).eq('id', i.id)
        }
      }
      return i
    })
    localStorage.setItem('local_investments', JSON.stringify(investments.value))
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


onMounted(() => {
  fetchAllData()
})

onActivated(() => {
  fetchAllData()
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
            <div class="group-wrapper" v-if="totalLiquidAssets > 0 || accounts.length === 0">
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

            <!-- Card: 投資 -->
            <div class="group-wrapper" v-if="totalInvestments > 0">
              <div class="group-header-card" :class="{ 'expanded-header bg-invest': listExpanded.invest }" @click="toggleListExpand('invest')" style="cursor: pointer;">
                <div class="card-header-main-row">
                  <span class="group-title-text" :class="{ 'text-dark': !listExpanded.invest, 'text-white': listExpanded.invest }">投資</span>
                  <span class="group-value-text" :class="{ 'text-dark': !listExpanded.invest, 'text-white': listExpanded.invest }">{{ isHidden ? '••••••' : formatCurrency(totalInvestments).replace('$', '') }}</span>
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
                        <!-- Circular Percentage Badge (showing percentage of total investments) -->
                        <div class="sub-item-badge" style="background: rgba(92, 103, 245, 0.1); color: #5c67f5; font-weight: 800;">
                          {{ Math.round(item.percentage) }}%
                        </div>
                        
                        <!-- Details -->
                        <div class="sub-item-info">
                          <div class="sub-item-name">{{ item.name }}</div>
                          <div class="sub-item-desc">{{ item.desc }}</div>
                        </div>

                        <!-- Value & Date -->
                        <div class="sub-item-right">
                          <div class="sub-item-val">
                            {{ isHidden ? '••••••' : formatCurrency(item.valueTwd).replace('$', '') }}
                          </div>
                          <div class="sub-item-date">{{ item.isGroup ? '群組' : formatDate(item.price_updated_at) }}</div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Card: 固定資產 -->
            <div class="group-wrapper" v-if="totalFixedAssets > 0">
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
            <div class="group-wrapper" v-if="totalReceivables > 0">
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
            <div class="group-wrapper" v-if="totalLiabilities > 0">
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
        <div style="display: flex; background: rgba(0, 0, 0, 0.04); padding: 4px; border-radius: 20px; margin-top: 18px; margin-bottom: 20px;">
          <button 
            @click="trendType = 'net_worth'"
            :style="{
              flex: 1,
              padding: '10px 0',
              borderRadius: '16px',
              border: 'none',
              fontSize: '0.9rem',
              fontWeight: '700',
              cursor: 'pointer',
              background: trendType === 'net_worth' ? '#ffffff' : 'transparent',
              color: trendType === 'net_worth' ? 'var(--color-text)' : 'var(--color-text-muted)',
              boxShadow: trendType === 'net_worth' ? '0 2px 4px rgba(0,0,0,0.05)' : 'none'
            }"
          >
            淨資產與負債
          </button>
          <button 
            @click="trendType = 'liquid_invest'"
            :style="{
              flex: 1,
              padding: '10px 0',
              borderRadius: '16px',
              border: 'none',
              fontSize: '0.9rem',
              fontWeight: '700',
              cursor: 'pointer',
              background: trendType === 'liquid_invest' ? '#ffffff' : 'transparent',
              color: trendType === 'liquid_invest' ? 'var(--color-text)' : 'var(--color-text-muted)',
              boxShadow: trendType === 'liquid_invest' ? '0 2px 4px rgba(0,0,0,0.05)' : 'none'
            }"
          >
            流動資金與投資
          </button>
        </div>
      </div>

      <!-- Scrollable Contents -->
      <div style="flex: 1; overflow-y: auto; padding: 0 16px; box-sizing: border-box; -webkit-overflow-scrolling: touch;">
        <!-- Date Range & Summary Info -->
        <div style="text-align: left; padding: 0 4px; margin-bottom: 24px;">
          <div style="font-size: 0.85rem; color: var(--color-text-muted); font-weight: bold; margin-bottom: 10px;">
            {{ trendDateRangeText }}
          </div>
          <template v-if="trendType === 'net_worth'">
            <div style="font-size: 0.95rem; font-weight: 700; color: var(--color-text); line-height: 1.6;">
              {{ netWorthSummaryText.nw }}
            </div>
            <div style="font-size: 0.95rem; font-weight: 700; color: var(--color-text); line-height: 1.6; margin-top: 4px;">
              {{ netWorthSummaryText.liab }}
            </div>
          </template>
          <template v-else>
            <div style="font-size: 0.95rem; font-weight: 700; color: var(--color-text); line-height: 1.6;">
              {{ liquidInvestSummaryText.liquid }}
            </div>
            <div style="font-size: 0.95rem; font-weight: 700; color: var(--color-text); line-height: 1.6; margin-top: 4px;">
              {{ liquidInvestSummaryText.invest }}
            </div>
          </template>
        </div>

        <!-- Legend -->
        <div style="display: flex; gap: 24px; align-items: center; margin-bottom: 24px; padding-left: 12px;">
          <template v-if="trendType === 'net_worth'">
            <div style="display: flex; align-items: center; gap: 6px; font-size: 0.82rem; font-weight: bold; color: var(--color-text);">
              <span style="display: inline-block; width: 12px; height: 12px; background: #5c67f5; border-radius: 2px;"></span>
              我的淨資產
            </div>
            <div style="display: flex; align-items: center; gap: 6px; font-size: 0.82rem; font-weight: bold; color: var(--color-text);">
              <!-- Dotted box indicator matching native design -->
              <span style="display: inline-flex; width: 12px; height: 12px; border: 1.5px dashed #a0a0a5; box-sizing: border-box; border-radius: 2px;"></span>
              負債
            </div>
          </template>
          <template v-else>
            <div style="display: flex; align-items: center; gap: 6px; font-size: 0.82rem; font-weight: bold; color: var(--color-text);">
              <span style="display: inline-block; width: 12px; height: 12px; background: #2ec173; border-radius: 2px;"></span>
              流動資金
            </div>
            <div style="display: flex; align-items: center; gap: 6px; font-size: 0.82rem; font-weight: bold; color: var(--color-text);">
              <span style="display: inline-block; width: 12px; height: 12px; background: #7839ec; border-radius: 2px;"></span>
              投資
            </div>
          </template>
        </div>

        <!-- Line Chart Container -->
        <div style="height: 260px; position: relative; margin-bottom: 32px;">
          <Line :data="trendChartData" :options="trendChartOptions" />
        </div>

        <!-- Custom Date Picker Row -->
        <div v-if="timeFilter === 'ALL'" style="display: flex; gap: 12px; align-items: center; margin-bottom: 20px; padding: 0 4px; width: 100%; box-sizing: border-box;">
          <div style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 4px; text-align: left;">
            <span style="font-size: 0.75rem; color: var(--color-text-muted); font-weight: bold;">開始日期</span>
            <input type="date" v-model="customStartDate" class="reset-input" style="background: #f1f5f9 !important; border: 1px solid rgba(0,0,0,0.08) !important; color: var(--color-text) !important; padding: 8px 12px !important; border-radius: 12px !important; font-size: 0.85rem !important; width: 100% !important; box-sizing: border-box !important; outline: none; margin: 0 !important; height: auto !important; line-height: normal !important;" />
          </div>
          <div style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 4px; text-align: left;">
            <span style="font-size: 0.75rem; color: var(--color-text-muted); font-weight: bold;">結束日期</span>
            <input type="date" v-model="customEndDate" class="reset-input" style="background: #f1f5f9 !important; border: 1px solid rgba(0,0,0,0.08) !important; color: var(--color-text) !important; padding: 8px 12px !important; border-radius: 12px !important; font-size: 0.85rem !important; width: 100% !important; box-sizing: border-box !important; outline: none; margin: 0 !important; height: auto !important; line-height: normal !important;" />
          </div>
        </div>

        <!-- Capsule Time Filter Selector -->
        <div style="display: flex; background: rgba(0, 0, 0, 0.04); padding: 4px; border-radius: 25px; gap: 4px; margin-bottom: 20px;">
          <button 
            v-for="time in [
              { label: '30天', value: '30D' },
              { label: '6月', value: '6M' },
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

        <!-- Bottom spacer to prevent overlap with floating BottomNav -->
        <div style="height: 110px; flex-shrink: 0;"></div>
      </div>
    </div>

    <!-- ── 3. 資料管理視圖 (Settings Tab) ────────────────────────────── -->
    <div v-else-if="currentTab === 'settings'" key="settings" class="tab-view-content" style="gap: 1rem;">
      <div class="settings-header-row">
        <h3>管理所有原始帳目</h3>
        <button class="icon-text-btn" @click="refreshPrices" :disabled="isRefreshing">
          <PhArrowClockwise size="16" :class="{ spin: isRefreshing }" />
          <span>{{ isRefreshing ? '更新中' : '更新最新股價' }}</span>
        </button>
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
              <span class="item-value">{{ formatCurrency(acc.balance) }}</span>
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
              <span class="item-type-badge">{{ translateTypeSettings(inv.asset_class) }} · {{ inv.quantity }} 單位 @ {{ inv.currency }} {{ inv.buy_price }}</span>
            </div>
            <div class="item-right-wrap">
              <span class="item-value">{{ formatCurrency(inv.quantity * inv.current_price) }}</span>
              <button class="delete-btn" @click.stop="deleteInvestment(inv.id)" title="刪除">
                <PhTrash size="16" />
              </button>
            </div>
          </div>
        </div>
        <div v-else class="settings-empty">目前尚無投資資料</div>
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
                <div class="row-label-group" style="display: flex; align-items: center; gap: 4px;">
                  <span class="row-label">股票代號</span>
                  <PhInfo size="14" style="color: var(--color-text-muted); opacity: 0.8;" />
                </div>
                <input v-model="newAsset.symbol" :placeholder="newAsset.type === 'Stock' ? 'TSLA 或 0050' : 'BTC'" class="input-flat-right text-right" style="text-transform: uppercase; font-weight: 700; width: 120px;" />
              </div>

              <!-- 股數 (With Stacked Subtext) -->
              <div class="form-item-row-stacked" style="padding: 14px 18px; border-bottom: 1px solid rgba(255, 255, 255, 0.05); display: flex; flex-direction: column;">
                <div style="display: flex; justify-content: space-between; align-items: center; width: 100%;">
                  <span class="row-label">股數</span>
                  <div class="row-value-wrapper" style="display: flex; align-items: center; gap: 8px;">
                    <input v-model.number="newAsset.quantity" type="number" step="0.0001" placeholder="0" class="input-flat-right text-right" style="font-weight: 700; font-size: 1.15rem; width: 120px;" />
                    <span class="currency-badge" style="background: rgba(255,255,255,0.08); padding: 4px 8px; border-radius: 6px; font-size: 0.75rem; font-weight: 700;">{{ isTaiwanStock(newAsset.symbol) ? 'TWD' : 'USD' }}</span>
                  </div>
                </div>
                <!-- Subtext Row -->
                <div style="display: flex; justify-content: space-between; align-items: center; width: 100%; margin-top: 8px; font-size: 0.8rem; color: var(--color-text-muted);">
                  <!-- Left side: Edit buy price inline -->
                  <div style="display: flex; align-items: center; gap: 4px;">
                    <span>單價:</span>
                    <span style="color: white; font-weight: 600; display: flex; align-items: center; gap: 2px;">
                      {{ isTaiwanStock(newAsset.symbol) ? 'TWD' : 'USD' }}
                      <input v-model.number="newAsset.buy_price" type="number" step="0.01" class="input-flat-right text-right" style="width: 70px; background: transparent; border: none; border-bottom: 1px dashed rgba(255,255,255,0.3); color: white; padding: 0 4px; font-weight: 700; font-size: 0.8rem; margin: 0;" />
                    </span>
                  </div>
                  <!-- Right side: computed total value -->
                  <span style="font-weight: 600; color: rgba(255,255,255,0.5);">
                    = {{ isTaiwanStock(newAsset.symbol) ? 'TWD' : 'USD' }} {{ formatInvestNumber(Number(newAsset.quantity || 0) * Number(newAsset.buy_price || 0)) }}
                  </span>
                </div>
              </div>

              <!-- 自定名稱 -->
              <div class="form-item-row">
                <span class="row-label">自定名稱</span>
                <input v-model="newAsset.name" placeholder="例: 元大台灣 50" class="input-flat-right text-right" />
              </div>

              <!-- 連結扣款帳戶 -->
              <div class="form-item-row" style="position: relative;">
                <span class="row-label">連結扣款帳戶</span>
                <div class="row-value-wrapper">
                  <span class="display-val" style="color: #ffffff; font-size: 0.95rem; font-weight: 700;">
                    {{ accounts.find(a => a.id === newAsset.funding_account_id)?.name || '不連結扣款' }}
                  </span>
                  <PhCaretRight size="16" class="chevron-icon" />
                </div>
                <select v-model="newAsset.funding_account_id" class="invisible-select">
                  <option :value="null">不連結扣款</option>
                  <option 
                    v-for="acc in accounts.filter(a => ['Bank', 'Cash', 'E-Wallet', 'OtherLiquid'].includes(a.type))" 
                    :key="acc.id" 
                    :value="acc.id"
                  >
                    {{ acc.name }} ({{ translateTypeSettings(acc.type) }})
                  </option>
                </select>
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
              <div class="form-item-row" style="border-bottom: none;">
                <span class="row-label">備註</span>
                <input v-model="newAsset.remarks" placeholder="輸入備註" class="input-flat-right text-right" />
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
                  <span class="currency-badge">TWD</span>
                </div>
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
            <div class="auto-record-bar-row">
              <div class="auto-record-left">
                <PhArrowClockwise size="20" class="auto-record-icon" />
                <span>自動記</span>
              </div>
              <button v-if="!newAsset.auto_record" type="button" class="btn-add-auto-record" @click="initAutoRecord">
                新增自動記
              </button>
              <div v-else class="auto-record-info-badge">
                <button type="button" class="btn-add-auto-record" @click="enterAutoRecordConfig" style="border-color: #3a59cc; color: #3a59cc;">
                  {{ newAsset.auto_record.type === 'income' ? '固定收入' : '固定支出' }} 每月{{ newAsset.auto_record.day }}日
                </button>
                <button type="button" class="badge-clear-btn" @click="newAsset.auto_record = null">清除</button>
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
          <button class="nav-save-circle" @click="addModalStep = 2" title="確定">
            <PhCheck size="20" weight="bold" />
          </button>
        </div>

        <div class="form-body" v-if="newAsset.auto_record">
          <!-- Tabs Segmented Control -->
          <div class="segmented-control" style="background-color: rgba(0, 0, 0, 0.04); border-radius: 14px; padding: 4px; display: flex;">
            <button 
              type="button" 
              class="seg-btn active-income" 
              :class="{ active: newAsset.auto_record.type === 'income' }"
              style="border-radius: 10px; flex: 1;"
              @click="newAsset.auto_record.type = 'income'; newAsset.auto_record.target_account_id = null"
            >
              固定收入
            </button>
            <button 
              type="button" 
              class="seg-btn active-expense" 
              :class="{ active: newAsset.auto_record.type === 'expense' }"
              style="border-radius: 10px; flex: 1;"
              @click="newAsset.auto_record.type = 'expense'; newAsset.auto_record.target_account_id = null"
            >
              固定支出
            </button>
            <button 
              type="button" 
              class="seg-btn" 
              :style="{ background: newAsset.auto_record.type === 'transfer' ? '#3a59cc' : 'transparent', color: newAsset.auto_record.type === 'transfer' ? '#ffffff' : 'var(--color-text-muted)' }"
              :class="{ active: newAsset.auto_record.type === 'transfer' }"
              style="border-radius: 10px; flex: 1; font-weight: 700;"
              @click="newAsset.auto_record.type = 'transfer'"
            >
              定期轉帳
            </button>
          </div>

          <!-- Card 1 -->
          <div class="form-card-black">
            <div class="form-item-row">
              <div class="row-label-group">
                <span class="row-label">金額</span>
                <span class="row-sublabel">TWD</span>
              </div>
              <div class="row-value-wrapper">
                <input v-model.number="newAsset.auto_record.amount" type="number" placeholder="0" class="input-flat-right" />
                <button type="button" class="minus-circle-btn" @click="newAsset.auto_record.amount = 0">
                  <PhMinusCircle size="20" weight="bold" />
                </button>
              </div>
            </div>
            
            <div class="form-item-row" style="position: relative;">
              <span class="row-label">記錄日期</span>
              <div class="row-value-wrapper">
                <span class="display-val" style="color: var(--color-text-muted); font-size: 0.95rem; font-weight: 700;">每月{{ newAsset.auto_record.day }}日</span>
                <PhCaretRight size="16" class="chevron-icon" />
              </div>
              <select v-model.number="newAsset.auto_record.day" class="invisible-select">
                <option v-for="d in 28" :key="d" :value="d">每月{{ d }}日</option>
              </select>
            </div>

            <!-- Target Account (Only for Transfer type) -->
            <div v-if="newAsset.auto_record.type === 'transfer'" class="form-item-row" style="position: relative; border-bottom: none;">
              <span class="row-label">轉入目標帳戶</span>
              <div class="row-value-wrapper">
                <span class="display-val" style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">
                  {{ accounts.find(a => a.id === newAsset.auto_record.target_account_id)?.name || '請選擇帳戶' }}
                </span>
                <PhCaretRight size="16" class="chevron-icon" />
              </div>
              <select v-model="newAsset.auto_record.target_account_id" class="invisible-select">
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

            <div class="form-item-row" style="border-bottom: none;">
              <span class="row-label">標籤</span>
              <input v-model="newAsset.auto_record.tag" placeholder="#輸入標籤" class="input-flat-right text-right red-text red-placeholder" @input="handleTagInput" />
            </div>
          </div>

          <div class="next-time-hint">
            下次記錄時間：{{ nextRecordDateStr }}
          </div>

          <!-- Card 2 -->
          <div class="form-card-black">
            <div class="form-item-row" style="border-bottom: none;">
              <span class="row-label">有效期</span>
              <div class="expiry-pill-selector">
                <button type="button" class="expiry-pill" :class="{ active: newAsset.auto_record.expiry === 'forever' }" @click="newAsset.auto_record.expiry = 'forever'">
                  永遠
                </button>
                <button type="button" class="expiry-pill" :class="{ active: newAsset.auto_record.expiry === 'custom' }" @click="newAsset.auto_record.expiry = 'custom'">
                  自訂
                </button>
              </div>
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
              {{ formatInvestCurrency(selectedInvestment.value, selectedInvestment.currency) }}
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
              <span style="color: var(--color-text-muted); font-size: 0.9rem; font-weight: 700;">變動記錄</span>
              <span style="color: var(--color-text-muted); font-size: 0.85rem; cursor: pointer; opacity: 0.7;">⚙️</span>
            </div>

            <!-- List of Lots -->
            <div style="display: flex; flex-direction: column; gap: 14px;">
              <div v-for="lot in selectedInvestment.lots" :key="lot.id" class="history-item-row" style="display: flex; justify-content: space-between; align-items: flex-start; padding-bottom: 14px; border-bottom: 1px solid rgba(0,0,0,0.04);">
                <div style="display: flex; flex-direction: column;">
                  <span style="color: var(--color-text); font-size: 0.95rem; font-weight: 700;">修改餘額</span>
                  <span style="color: var(--color-text-muted); font-size: 0.82rem; margin-top: 4px;">持有 {{ formatInvestNumber(lot.quantity) }}, {{ lot.currency }} {{ formatInvestNumber(lot.buy_price) }}</span>
                  <span style="color: var(--color-text-muted); opacity: 0.8; font-size: 0.8rem; margin-top: 4px;">{{ formatDateDetailed(lot.buy_date || lot.created_at) }}</span>
                </div>
                <div style="display: flex; flex-direction: column; align-items: flex-end;">
                  <span style="color: #2ec173; font-size: 0.95rem; font-weight: 700;">+{{ formatHistoryValue(lot.quantity * lot.current_price, lot.currency) }}</span>
                  <span style="color: var(--color-text-muted); font-size: 0.82rem; margin-top: 4px;">餘額 {{ formatHistoryValue(lot.quantity * lot.current_price, lot.currency) }}</span>
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

        <!-- Add item to group -->
        <div style="display: flex; flex-direction: column; gap: 0.5rem; background: rgba(0,0,0,0.02); padding: 1rem; border-radius: 12px; box-sizing: border-box;">
          <label style="font-size: 0.85rem; color: var(--color-text); font-weight: bold; text-align: left; display: block;">加到群組</label>
          <div style="display: flex; gap: 8px; width: 100%; box-sizing: border-box;">
            <select v-model="selectedItemToAddToGroup" style="flex: 1; height: 40px; padding: 0 10px; border-radius: 10px; border: 1px solid rgba(0,0,0,0.08); background: white; color: var(--color-text); font-size: 0.9rem; outline: none; width: 70%; min-width: 0;">
              <option value="" disabled>-- 選擇要加入的項目 --</option>
              <option v-for="item in getAvailableItemsForGroup" :key="item.id" :value="JSON.stringify({id: item.id, type: item.type})">
                {{ item.name }}
              </option>
            </select>
            <button @click="addItemToGroup" style="height: 40px; padding: 0 16px; background: var(--color-primary); color: white; border: none; font-weight: bold; border-radius: 10px; cursor: pointer; flex-shrink: 0;" :disabled="!selectedItemToAddToGroup">
              加入
            </button>
          </div>
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
          <div style="display: flex; justify-content: flex-end; align-items: center; margin-bottom: 20px; font-weight: 700; color: var(--color-text-muted); font-size: 0.95rem;">
            <span>合計 TWD </span>
            <span style="font-family: var(--font-display); font-size: 1.5rem; font-weight: 800; color: var(--color-text); margin-left: 8px;">
              {{ isHidden ? '••••••' : formatCurrency(activeGroupItems.reduce((sum, item) => sum + (activeCustomGroupCategory === 'invest' ? item.valueTwd : item.balance), 0)).replace('$', '') }}
            </span>
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
                  <div class="sub-item-desc">
                    持有 {{ item.qty }}, {{ item.currency }} {{ item.current_price }}
                  </div>
                </div>

                <!-- Value & Date -->
                <div class="sub-item-right">
                  <div class="sub-item-val">
                    {{ isHidden ? '••••••' : formatCurrency(item.valueTwd).replace('$', '') }}
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
  height: 100vh;
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
  height: 100vh;
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
  font-size: 0.95rem;
  font-weight: 700;
  height: 38px;
  border-radius: 9px;
  cursor: pointer;
  transition: all 0.2s ease;
  box-shadow: none !important;
}

.seg-btn.active-income.active {
  background: #2ebd59 !important;
  color: #ffffff !important;
}

.seg-btn.active-expense.active {
  background: #3a59cc !important;
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
</style>
