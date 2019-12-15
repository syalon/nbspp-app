package com.btsplusplus.fowallet
import android.os.Bundle
import android.support.design.widget.TabLayout
import android.support.v4.app.Fragment
import android.support.v4.view.ViewPager
import android.view.animation.OvershootInterpolator
import android.widget.TextView
import bitshares.toJsonArray
import bitshares.toList
import kotlinx.android.synthetic.main.activity_account_info.*
import kotlinx.android.synthetic.main.activity_my_orders.*
import kotlinx.android.synthetic.main.activity_otc_merchant_list.*
import org.json.JSONArray
import org.json.JSONObject
import java.lang.reflect.Field

class ActivityOtcMerchantList : BtsppActivity() {

    private val fragmens: ArrayList<Fragment> = ArrayList()
    private var tablayout: TabLayout? = null
    private var view_pager: ViewPager? = null

    private lateinit var _asset_name: String
    private lateinit var _data: JSONArray

    private lateinit var tv_asset_title: TextView


    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        //  设置自动布局
        setAutoLayoutContentView(R.layout.activity_otc_merchant_list)
        //  设置全屏(隐藏状态栏和虚拟导航栏)
        setFullScreen()

        //  Todo 获取参数
        // val args = btspp_args_as_JSONArray()
        // _asset_name  = args[0] as String
        _asset_name = "USD"

        // 设置 tablelayout 和 view_pager
        tablayout = tablayout_of_merchant_list
        view_pager = view_pager_of_merchant_list

        getData()

        // 添加 fargments
        setFragments()

        // 设置 viewPager 并配置滚动速度
        setViewPager()

        // 监听 tab 并设置选中 item
        setTabListener()

        // 根据 资产修改标题
        tv_asset_title = findViewById<TextView>(R.id.title)
        tv_asset_title.text = "${_asset_name} 市场◢"
        tv_asset_title.setOnClickListener {
            onSelectAssetClicked()
        }

        // 选择订单列表
        image_select_orders_from_merchant_list.setOnClickListener{
            goTo(ActivityOtcOrderList::class.java, true)
        }
        image_payments_from_merchant_list.setOnClickListener{

            val asset_list = JSONArray().apply {
                put("认证信息")
                put("收款方式")
            }
            ViewSelector.show(this, "添加收款方式", asset_list.toList<String>().toTypedArray()) { index: Int, _: String ->
                if (index == 0){
                    val is_user_auth = false
                    if (is_user_auth) {
                        goTo(ActivityOtcUserAuthInfos::class.java, true)
                    } else {
                        goTo(ActivityOtcUserAuth::class.java, true)
                    }
                } else {
                    goTo(ActivityOtcPaymentList::class.java, true)
                }
            }
        }

        //  返回
        layout_back_from_merchant_list.setOnClickListener { finish() }
    }

    private fun onSelectAssetClicked(){
        val asset_list = JSONArray().apply {
            put("CNY")
            put("USD")
            put("GDEX.CNY")
        }
        ViewSelector.show(this, "请选择要交易的资产", asset_list.toList<String>().toTypedArray()) { index: Int, _: String ->
            tv_asset_title.text = "${asset_list.getString(index)} 市场◢"
        }
    }

    private fun setViewPager() {
        view_pager!!.adapter = ViewPagerAdapter(super.getSupportFragmentManager(), fragmens)
        val f: Field = ViewPager::class.java.getDeclaredField("mScroller")
        f.isAccessible = true
        val vpc: ViewPagerScroller = ViewPagerScroller(view_pager!!.context, OvershootInterpolator(0.6f))
        f.set(view_pager, vpc)
        vpc.duration = 700

        view_pager!!.setOnPageChangeListener(object : ViewPager.OnPageChangeListener {
            override fun onPageScrollStateChanged(state: Int) {
            }

            override fun onPageScrolled(position: Int, positionOffset: Float, positionOffsetPixels: Int) {
            }

            override fun onPageSelected(position: Int) {
                println(position)
                tablayout!!.getTabAt(position)!!.select()
            }
        })
    }

    private fun getData() {
        _data = JSONArray().apply {
            for (i in 0 until 10){
                put(JSONObject().apply {
                    put("mmerchant_name","吉祥承兑")
                    put("total",3332)
                    put("rate","94%")
                    put("trade_count",1500)
                    put("legal_asset_symbol","¥")
                    put("limit_min","30")
                    put("limit_max","1250")
                    put("price","7.21")
                    put("ad_type",(1+ i % 2))
                    put("payment_methods", JSONArray().apply {
                        put("alipay")
                        put("bankcard")
                    })
                })
            }
        }
    }

    private fun setFragments() {

        // TODO 需要对 data 按买和卖分类传入
        val _args1 = JSONObject().apply {
            put("entry","otc_mc_list")
            put("data",_data)
            put("asset_name",_asset_name)
        }

        val _args2 = JSONObject().apply {
            put("entry","otc_ad_mc_list")
            put("data",_data)
            put("asset_name",_asset_name)
        }

        fragmens.add(FragmentOtcMerchantList().initialize(_args1))
        fragmens.add(FragmentOtcMerchantList().initialize(_args2))
    }

    private fun setTabListener() {
        tablayout!!.setOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
            override fun onTabSelected(tab: TabLayout.Tab) {
                view_pager!!.setCurrentItem(tab.position, true)
            }

            override fun onTabUnselected(tab: TabLayout.Tab) {
                //tab未被选择的时候回调
            }

            override fun onTabReselected(tab: TabLayout.Tab) {
                //tab重新选择的时候回调
            }
        })
    }


}