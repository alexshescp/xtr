package com.example.xtr

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColor
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class MainActivity : ComponentActivity() {
    private var isVpnActive by mutableStateOf(false)

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            startVpnService()
        } else {
            isVpnActive = false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            XtrTheme {
                MainScreen(
                    isActive = isVpnActive,
                    onToggle = {
                        if (!isVpnActive) {
                            val intent = VpnService.prepare(this)
                            if (intent != null) {
                                vpnPermissionLauncher.launch(intent)
                            } else {
                                startVpnService()
                            }
                        } else {
                            stopVpnService()
                        }
                    },
                    onChangeServer = {
                        if (isVpnActive) {
                            val intent = Intent(this, XrayService::class.java).apply { action = "NEXT" }
                            startService(intent)
                        }
                    }
                )
            }
        }
    }

    private fun startVpnService() {
        isVpnActive = true
        val intent = Intent(this, XrayService::class.java).apply { action = "START" }
        startService(intent)
    }

    private fun stopVpnService() {
        isVpnActive = false
        val intent = Intent(this, XrayService::class.java).apply { action = "STOP" }
        startService(intent)
    }
}

@Composable
fun MainScreen(isActive: Boolean, onToggle: () -> Unit, onChangeServer: () -> Unit) {
    val infiniteTransition = rememberInfiniteTransition(label = "background")
    val color1 by infiniteTransition.animateColor(
        initialValue = Color(0xFFE0F7FA),
        targetValue = Color(0xFFF3E5F5),
        animationSpec = infiniteRepeatable(
            animation = tween(4000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ), label = "c1"
    )
    val color2 by infiniteTransition.animateColor(
        initialValue = Color(0xFFF3E5F5),
        targetValue = Color(0xFFE8EAF6),
        animationSpec = infiniteRepeatable(
            animation = tween(5000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        ), label = "c2"
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Brush.linearGradient(listOf(color1, color2, color1)))
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "xTR",
                fontSize = 48.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF3F51B5),
                modifier = Modifier.padding(bottom = 8.dp)
            )
            Text(
                text = if (isActive) "CONNECTED" else "DISCONNECTED",
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = if (isActive) Color(0xFF4CAF50) else Color(0xFF757575),
                modifier = Modifier.padding(bottom = 48.dp)
            )

            Button(
                onClick = onToggle,
                modifier = Modifier
                    .width(200.dp)
                    .height(64.dp),
                shape = RoundedCornerShape(20.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (isActive) Color(0xFFE57373) else Color(0xFF3F51B5)
                ),
                elevation = ButtonDefaults.buttonElevation(defaultElevation = 8.dp)
            ) {
                Text(
                    text = if (isActive) "STOP" else "START",
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            if (isActive) {
                Spacer(modifier = Modifier.height(24.dp))
                OutlinedButton(
                    onClick = onChangeServer,
                    modifier = Modifier
                        .width(200.dp)
                        .height(56.dp),
                    shape = RoundedCornerShape(20.dp),
                    border = ButtonDefaults.outlinedButtonBorder.copy(width = 2.dp)
                ) {
                    Text(text = "CHANGE SERVER", color = Color(0xFF3F51B5))
                }
            }
        }
    }
}

@Composable
fun XtrTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Color(0xFF3F51B5),
            secondary = Color(0xFF03A9F4)
        ),
        content = content
    )
}
