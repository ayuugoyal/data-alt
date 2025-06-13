#!/usr/bin/env python3
"""
Multi-Sensor API Server for Raspberry Pi
Supports Ultrasonic (HC-SR04), MQ-135 Air Quality, and DHT11 Temperature/Humidity sensors
Exposes sensor data via FastAPI REST API
"""

import time
import json
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from threading import Thread, Lock
import asyncio
import logging

# Uncomment these imports when running on Raspberry Pi
# import RPi.GPIO as GPIO
# import Adafruit_DHT

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Data Models
class SensorReading(BaseModel):
    AlertType: str
    assetId: str
    Description: str
    Date: str
    Report: str
    App: str
    anchor: str
    Stage_x007b__x0023__x007d_: str
    Failure_x0020_Class: str
    id: str
    Priority: str
    OperatorNumber: str
    OperatorName: str
    ManagerName: str
    ManagerNumber: str
    GoogleDriveURL: str

class ApiResponse(BaseModel):
    success: bool
    data: List[Dict]
    shouldSubscribe: str

class BaseSensor:
    def __init__(self, sensor_id: str, asset_id: str):
        self.sensor_id = sensor_id
        self.asset_id = asset_id
        self.last_reading_time = None
        self.lock = Lock()
        self.alerts = []
        
    def generate_alert(self, alert_type: str, description: str, failure_class: str = "NaN") -> Dict:
        alert_id = f"{self.sensor_id}_{int(time.time())}"
        return {
            "AlertType": alert_type,
            "assetId": self.asset_id,
            "Description": description,
            "Date": datetime.now(timezone.utc).isoformat(),
            "Report": "NaN",
            "App": "IoT Sensor System",
            "anchor": self.asset_id,
            "Stage_x007b__x0023__x007d_": "NaN",
            "Failure_x0020_Class": failure_class,
            "id": alert_id,
            "Priority": "NaN",
            "OperatorNumber": "NaN",
            "OperatorName": "NaN",
            "ManagerName": "NaN",
            "ManagerNumber": "NaN",
            "GoogleDriveURL": "NaN"
        }

class UltrasonicSensor(BaseSensor):
    def __init__(self, sensor_id: str = "ULTRASONIC-01", asset_id: str = "DIST-SENSOR-01", 
                 trigger_pin: int = 18, echo_pin: int = 24):
        super().__init__(sensor_id, asset_id)
        self.trigger_pin = trigger_pin
        self.echo_pin = echo_pin
        self.distance = 0.0
        self.min_distance_threshold = 10.0  # cm
        self.max_distance_threshold = 200.0  # cm
        self.setup_gpio()
        
    def setup_gpio(self):
        """Initialize GPIO pins"""
        try:
            # Uncomment when running on Raspberry Pi
            # GPIO.setmode(GPIO.BCM)
            # GPIO.setup(self.trigger_pin, GPIO.OUT)
            # GPIO.setup(self.echo_pin, GPIO.IN)
            # GPIO.output(self.trigger_pin, False)
            logger.info(f"GPIO initialized - Trigger: {self.trigger_pin}, Echo: {self.echo_pin}")
        except Exception as e:
            logger.error(f"GPIO setup error: {e}")
        
    def measure_distance(self) -> Optional[float]:
        """Measure distance using ultrasonic sensor (HC-SR04)"""
        try:
            # Simulate reading for demo (remove when using real sensor)
            import random
            distance = random.uniform(5, 250)
            
            # Uncomment for real sensor implementation
            """
            GPIO.output(self.trigger_pin, True)
            time.sleep(0.00001)
            GPIO.output(self.trigger_pin, False)
            
            pulse_start = time.time()
            timeout = pulse_start + 0.1
            
            while GPIO.input(self.echo_pin) == 0:
                pulse_start = time.time()
                if pulse_start > timeout:
                    return None
                    
            pulse_end = time.time()
            timeout = pulse_end + 0.1
            
            while GPIO.input(self.echo_pin) == 1:
                pulse_end = time.time()
                if pulse_end > timeout:
                    return None
                    
            pulse_duration = pulse_end - pulse_start
            distance = (pulse_duration * 34300) / 2
            """
            
            return round(distance, 2)
            
        except Exception as e:
            logger.error(f"Error measuring distance: {e}")
            return None
            
    def update_reading(self):
        """Update the current distance reading and check for alerts"""
        distance = self.measure_distance()
        if distance is not None:
            with self.lock:
                self.distance = distance
                self.last_reading_time = datetime.now(timezone.utc)
                
                # Check for alerts
                if distance < self.min_distance_threshold:
                    alert = self.generate_alert(
                        "Proximity Alert",
                        f"Object detected within {self.min_distance_threshold}cm. Current distance: {distance}cm",
                        "Proximity_Warning"
                    )
                    self.alerts.append(alert)
                elif distance > self.max_distance_threshold:
                    alert = self.generate_alert(
                        "Range Alert",
                        f"No object detected within range. Current distance: {distance}cm",
                        "Range_Warning"
                    )
                    self.alerts.append(alert)
                    
    def get_reading(self) -> Dict:
        """Get the current distance reading"""
        with self.lock:
            return {
                'sensor_type': 'ultrasonic',
                'sensor_id': self.sensor_id,
                'distance_cm': self.distance,
                'distance_inches': round(self.distance / 2.54, 2),
                'timestamp': self.last_reading_time.isoformat() if self.last_reading_time else None,
                'status': 'active' if self.last_reading_time else 'no_reading',
                'pins': {'trigger': self.trigger_pin, 'echo': self.echo_pin}
            }

class MQ135Sensor(BaseSensor):
    def __init__(self, sensor_id: str = "MQ135-01", asset_id: str = "AIR-QUALITY-01", 
                 analog_pin: int = 0):  # MCP3008 channel
        super().__init__(sensor_id, asset_id)
        self.analog_pin = analog_pin
        self.air_quality_ppm = 0.0
        self.danger_threshold = 1000  # ppm
        self.warning_threshold = 500  # ppm
        
    def read_air_quality(self) -> Optional[float]:
        """Read air quality from MQ-135 sensor"""
        try:
            # Simulate reading for demo (remove when using real sensor)
            import random
            ppm = random.uniform(50, 1200)
            
            # Uncomment for real sensor implementation with MCP3008 ADC
            """
            import spidev
            spi = spidev.SpiDev()
            spi.open(0, 0)
            spi.max_speed_hz = 1000000
            
            adc_value = spi.xfer2([1, (8 + self.analog_pin) << 4, 0])
            data = ((adc_value[1] & 3) << 8) + adc_value[2]
            voltage = (data * 3.3) / 1024
            
            # Convert voltage to PPM (calibration required)
            ppm = voltage * 100  # Simplified conversion
            spi.close()
            """
            
            return round(ppm, 2)
            
        except Exception as e:
            logger.error(f"Error reading air quality: {e}")
            return None
            
    def update_reading(self):
        """Update air quality reading and check for alerts"""
        ppm = self.read_air_quality()
        if ppm is not None:
            with self.lock:
                self.air_quality_ppm = ppm
                self.last_reading_time = datetime.now(timezone.utc)
                
                # Check for alerts
                if ppm > self.danger_threshold:
                    alert = self.generate_alert(
                        "Air Quality Critical",
                        f"Dangerous air quality detected: {ppm} PPM. Immediate action required.",
                        "Air_Quality_Critical"
                    )
                    self.alerts.append(alert)
                elif ppm > self.warning_threshold:
                    alert = self.generate_alert(
                        "Air Quality Warning",
                        f"Poor air quality detected: {ppm} PPM. Monitor closely.",
                        "Air_Quality_Warning"
                    )
                    self.alerts.append(alert)
                    
    def get_reading(self) -> Dict:
        """Get current air quality reading"""
        with self.lock:
            quality_level = "Good"
            if self.air_quality_ppm > self.danger_threshold:
                quality_level = "Dangerous"
            elif self.air_quality_ppm > self.warning_threshold:
                quality_level = "Poor"
                
            return {
                'sensor_type': 'air_quality',
                'sensor_id': self.sensor_id,
                'air_quality_ppm': self.air_quality_ppm,
                'quality_level': quality_level,
                'timestamp': self.last_reading_time.isoformat() if self.last_reading_time else None,
                'status': 'active' if self.last_reading_time else 'no_reading',
                'pins': {'analog': self.analog_pin}
            }

class DHT11Sensor(BaseSensor):
    def __init__(self, sensor_id: str = "DHT11-01", asset_id: str = "TEMP-HUM-01", 
                 data_pin: int = 22):
        super().__init__(sensor_id, asset_id)
        self.data_pin = data_pin
        self.temperature = 0.0
        self.humidity = 0.0
        self.temp_high_threshold = 35.0  # Celsius
        self.temp_low_threshold = 5.0    # Celsius
        self.humidity_high_threshold = 80.0  # %
        self.humidity_low_threshold = 20.0   # %
        
    def read_temp_humidity(self) -> tuple:
        """Read temperature and humidity from DHT11"""
        try:
            # Simulate reading for demo (remove when using real sensor)
            import random
            humidity = random.uniform(30, 90)
            temperature = random.uniform(15, 40)
            
            # Uncomment for real sensor implementation
            """
            humidity, temperature = Adafruit_DHT.read_retry(Adafruit_DHT.DHT11, self.data_pin)
            """
            
            return humidity, temperature
            
        except Exception as e:
            logger.error(f"Error reading DHT11: {e}")
            return None, None
            
    def update_reading(self):
        """Update temperature and humidity readings and check for alerts"""
        humidity, temperature = self.read_temp_humidity()
        if humidity is not None and temperature is not None:
            with self.lock:
                self.humidity = round(humidity, 2)
                self.temperature = round(temperature, 2)
                self.last_reading_time = datetime.now(timezone.utc)
                
                # Check for temperature alerts
                if temperature > self.temp_high_threshold:
                    alert = self.generate_alert(
                        "Temperature Alert",
                        f"High temperature detected: {temperature}°C",
                        "Temperature_High"
                    )
                    self.alerts.append(alert)
                elif temperature < self.temp_low_threshold:
                    alert = self.generate_alert(
                        "Temperature Alert",
                        f"Low temperature detected: {temperature}°C",
                        "Temperature_Low"
                    )
                    self.alerts.append(alert)
                    
                # Check for humidity alerts
                if humidity > self.humidity_high_threshold:
                    alert = self.generate_alert(
                        "Humidity Alert",
                        f"High humidity detected: {humidity}%",
                        "Humidity_High"
                    )
                    self.alerts.append(alert)
                elif humidity < self.humidity_low_threshold:
                    alert = self.generate_alert(
                        "Humidity Alert",
                        f"Low humidity detected: {humidity}%",
                        "Humidity_Low"
                    )
                    self.alerts.append(alert)
                    
    def get_reading(self) -> Dict:
        """Get current temperature and humidity reading"""
        with self.lock:
            return {
                'sensor_type': 'temperature_humidity',
                'sensor_id': self.sensor_id,
                'temperature_celsius': self.temperature,
                'temperature_fahrenheit': round((self.temperature * 9/5) + 32, 2),
                'humidity_percent': self.humidity,
                'timestamp': self.last_reading_time.isoformat() if self.last_reading_time else None,
                'status': 'active' if self.last_reading_time else 'no_reading',
                'pins': {'data': self.data_pin}
            }

# Initialize sensors
ultrasonic_sensor = UltrasonicSensor()
mq135_sensor = MQ135Sensor()
dht11_sensor = DHT11Sensor()

sensors = {
    'ultrasonic': ultrasonic_sensor,
    'mq135': mq135_sensor,
    'dht11': dht11_sensor
}

# FastAPI app
app = FastAPI(
    title="Multi-Sensor IoT API",
    description="REST API for Ultrasonic, MQ-135, and DHT11 sensors on Raspberry Pi",
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

@app.get("/", response_class=HTMLResponse)
async def home():
    """API documentation homepage"""
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Multi-Sensor IoT API</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .endpoint { background: #f5f5f5; padding: 10px; margin: 10px 0; border-radius: 5px; }
            .method { color: #007acc; font-weight: bold; }
        </style>
    </head>
    <body>
        <h1>Multi-Sensor IoT API v2.0.0</h1>
        <h2>Available Endpoints:</h2>
        
        <div class="endpoint">
            <span class="method">GET</span> <strong>/docs</strong> - Interactive API Documentation (Swagger UI)
        </div>
        <div class="endpoint">
            <span class="method">GET</span> <strong>/redoc</strong> - Alternative API Documentation (ReDoc)
        </div>
        <div class="endpoint">
            <span class="method">GET</span> <strong>/sensors</strong> - Get all sensor readings
        </div>
        <div class="endpoint">
            <span class="method">GET</span> <strong>/sensors/alerts</strong> - Get all sensor alerts in specified format
        </div>
        <div class="endpoint">
            <span class="method">GET</span> <strong>/sensors/{sensor_type}</strong> - Get specific sensor reading
        </div>
        <div class="endpoint">
            <span class="method">GET</span> <strong>/sensors/{sensor_type}/live</strong> - Get fresh sensor reading
        </div>
        <div class="endpoint">
            <span class="method">GET</span> <strong>/health</strong> - Health check all sensors
        </div>
        <div class="endpoint">
            <span class="method">GET</span> <strong>/config</strong> - Get sensor configurations
        </div>
        
        <h2>Supported Sensors:</h2>
        <ul>
            <li><strong>ultrasonic</strong> - HC-SR04 Distance Sensor (Pins: Trigger=18, Echo=24)</li>
            <li><strong>mq135</strong> - MQ-135 Air Quality Sensor (Pin: Analog=0 via MCP3008)</li>
            <li><strong>dht11</strong> - DHT11 Temperature/Humidity Sensor (Pin: Data=22)</li>
        </ul>
        
        <h2>Pin Connections:</h2>
        <h3>HC-SR04 Ultrasonic Sensor:</h3>
        <ul>
            <li>VCC → 5V</li>
            <li>GND → Ground</li>
            <li>Trig → GPIO 18</li>
            <li>Echo → GPIO 24</li>
        </ul>
        
        <h3>MQ-135 Air Quality Sensor:</h3>
        <ul>
            <li>VCC → 5V</li>
            <li>GND → Ground</li>
            <li>A0 → MCP3008 CH0 → SPI (CE0)</li>
            <li>D0 → Not used</li>
        </ul>
        
        <h3>DHT11 Temperature/Humidity Sensor:</h3>
        <ul>
            <li>VCC → 3.3V</li>
            <li>GND → Ground</li>
            <li>Data → GPIO 22</li>
            <li>Pull-up resistor (10kΩ) between VCC and Data</li>
        </ul>
    </body>
    </html>
    """
    return html_content

@app.get("/sensors", response_model=ApiResponse)
async def get_all_sensors():
    """Get readings from all sensors"""
    try:
        readings = []
        for sensor_type, sensor in sensors.items():
            readings.append(sensor.get_reading())
        
        return ApiResponse(
            success=True,
            data=readings,
            shouldSubscribe="true"
        )
    except Exception as e:
        logger.error(f"Error getting all sensors: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/sensors/alerts", response_model=ApiResponse)
async def get_sensor_alerts():
    """Get all sensor alerts in the specified format"""
    try:
        all_alerts = []
        
        # Collect alerts from all sensors
        for sensor in sensors.values():
            with sensor.lock:
                all_alerts.extend(sensor.alerts[-10:])  # Last 10 alerts per sensor
        
        # Sort by date (newest first)
        all_alerts.sort(key=lambda x: x['Date'], reverse=True)
        
        return ApiResponse(
            success=True,
            data=all_alerts,
            shouldSubscribe="true"
        )
    except Exception as e:
        logger.error(f"Error getting sensor alerts: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/sensors/{sensor_type}", response_model=ApiResponse)
async def get_sensor(sensor_type: str):
    """Get reading from a specific sensor"""
    if sensor_type not in sensors:
        raise HTTPException(
            status_code=404, 
            detail=f"Sensor type '{sensor_type}' not found. Available: {list(sensors.keys())}"
        )
    
    try:
        reading = [sensors[sensor_type].get_reading()]
        return ApiResponse(
            success=True,
            data=reading,
            shouldSubscribe="true"
        )
    except Exception as e:
        logger.error(f"Error getting {sensor_type} sensor: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/sensors/{sensor_type}/live", response_model=ApiResponse)
async def get_live_sensor(sensor_type: str):
    """Get a fresh reading from a specific sensor"""
    if sensor_type not in sensors:
        raise HTTPException(
            status_code=404, 
            detail=f"Sensor type '{sensor_type}' not found. Available: {list(sensors.keys())}"
        )
    
    try:
        sensors[sensor_type].update_reading()
        reading = [sensors[sensor_type].get_reading()]
        return ApiResponse(
            success=True,
            data=reading,
            shouldSubscribe="true",
            note="Fresh measurement taken"
        )
    except Exception as e:
        logger.error(f"Error getting live {sensor_type} sensor: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check for all sensors"""
    try:
        health_status = {}
        overall_healthy = True
        
        for sensor_type, sensor in sensors.items():
            try:
                sensor.update_reading()
                reading = sensor.get_reading()
                is_healthy = reading['status'] == 'active'
                health_status[sensor_type] = {
                    'healthy': is_healthy,
                    'last_reading': reading['timestamp'],
                    'sensor_id': reading['sensor_id']
                }
                if not is_healthy:
                    overall_healthy = False
            except Exception as e:
                health_status[sensor_type] = {
                    'healthy': False,
                    'error': str(e)
                }
                overall_healthy = False
        
        return {
            'success': True,
            'data': [{
                'status': 'healthy' if overall_healthy else 'degraded',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'sensors': health_status
            }],
            'shouldSubscribe': "true"
        }
    except Exception as e:
        logger.error(f"Health check error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/config")
async def get_config():
    """Get configuration for all sensors"""
    config = []
    for sensor_type, sensor in sensors.items():
        reading = sensor.get_reading()
        config.append({
            'sensor_id': reading['sensor_id'],
            'sensor_type': reading['sensor_type'],
            'pins': reading['pins'],
            'asset_id': sensor.asset_id
        })
    
    return {
        'success': True,
        'data': config,
        'shouldSubscribe': "true",
        'api_version': '2.0.0',
        'update_interval': '1_second'
    }

def continuous_reading():
    """Background task for continuous sensor readings"""
    while True:
        try:
            for sensor in sensors.values():
                sensor.update_reading()
            time.sleep(1)  # Update every second
        except Exception as e:
            logger.error(f"Error in continuous reading: {e}")
            time.sleep(5)

@app.on_event("startup")
async def startup_event():
    """Start background tasks when the app starts"""
    # Start background reading thread
    reading_thread = Thread(target=continuous_reading, daemon=True)
    reading_thread.start()
    logger.info("Background reading thread started")
    logger.info("Multi-Sensor API Server started")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup when the app shuts down"""
    try:
        # Uncomment when using real GPIO
        # GPIO.cleanup()
        logger.info("GPIO cleaned up")
    except Exception as e:
        logger.error(f"Cleanup error: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)