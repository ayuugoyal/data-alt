#!/usr/bin/env python3
"""
Ultrasonic Sensor API Server for Raspberry Pi
Exposes ultrasonic sensor data via REST API
"""

import time
import json
from datetime import datetime
from flask import Flask, jsonify, request
from threading import Thread, Lock
import RPi.GPIO as GPIO
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class UltrasonicSensor:
    def __init__(self, trigger_pin=18, echo_pin=24):
        self.trigger_pin = trigger_pin
        self.echo_pin = echo_pin
        self.distance = 0.0
        self.last_reading_time = None
        self.lock = Lock()
        self.setup_gpio()
        
    def setup_gpio(self):
        """Initialize GPIO pins"""
        GPIO.setmode(GPIO.BCM)
        GPIO.setup(self.trigger_pin, GPIO.OUT)
        GPIO.setup(self.echo_pin, GPIO.IN)
        GPIO.output(self.trigger_pin, False)
        logger.info(f"GPIO initialized - Trigger: {self.trigger_pin}, Echo: {self.echo_pin}")
        
    def measure_distance(self):
        """Measure distance using ultrasonic sensor (HC-SR04)"""
        try:
            # Send trigger pulse
            GPIO.output(self.trigger_pin, True)
            time.sleep(0.00001)  # 10 microseconds
            GPIO.output(self.trigger_pin, False)
            
            # Wait for echo start
            pulse_start = time.time()
            timeout = pulse_start + 0.1  # 100ms timeout
            
            while GPIO.input(self.echo_pin) == 0:
                pulse_start = time.time()
                if pulse_start > timeout:
                    return None
                    
            # Wait for echo end
            pulse_end = time.time()
            timeout = pulse_end + 0.1
            
            while GPIO.input(self.echo_pin) == 1:
                pulse_end = time.time()
                if pulse_end > timeout:
                    return None
                    
            # Calculate distance (speed of sound = 34300 cm/s)
            pulse_duration = pulse_end - pulse_start
            distance = (pulse_duration * 34300) / 2
            
            return round(distance, 2)
            
        except Exception as e:
            logger.error(f"Error measuring distance: {e}")
            return None
            
    def update_reading(self):
        """Update the current distance reading"""
        distance = self.measure_distance()
        if distance is not None:
            with self.lock:
                self.distance = distance
                self.last_reading_time = datetime.now()
                
    def get_reading(self):
        """Get the current distance reading"""
        with self.lock:
            return {
                'distance_cm': self.distance,
                'distance_inches': round(self.distance / 2.54, 2),
                'timestamp': self.last_reading_time.isoformat() if self.last_reading_time else None,
                'status': 'active' if self.last_reading_time else 'no_reading'
            }
            
    def cleanup(self):
        """Clean up GPIO resources"""
        GPIO.cleanup()

# Initialize sensor
sensor = UltrasonicSensor()

# Flask app
app = Flask(__name__)

@app.route('/')
def home():
    """API documentation endpoint"""
    return jsonify({
        'message': 'Ultrasonic Sensor API',
        'version': '1.0',
        'endpoints': {
            '/': 'API documentation',
            '/distance': 'Get current distance reading',
            '/distance/live': 'Get live distance reading (forces new measurement)',
            '/health': 'Health check',
            '/config': 'Get sensor configuration'
        }
    })

@app.route('/distance')
def get_distance():
    """Get the current cached distance reading"""
    try:
        reading = sensor.get_reading()
        return jsonify({
            'success': True,
            'data': reading
        })
    except Exception as e:
        logger.error(f"Error getting distance: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/distance/live')
def get_live_distance():
    """Get a fresh distance reading"""
    try:
        sensor.update_reading()
        reading = sensor.get_reading()
        return jsonify({
            'success': True,
            'data': reading,
            'note': 'Fresh measurement taken'
        })
    except Exception as e:
        logger.error(f"Error getting live distance: {e}")
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/health')
def health_check():
    """Health check endpoint"""
    try:
        # Test sensor by taking a reading
        test_distance = sensor.measure_distance()
        status = 'healthy' if test_distance is not None else 'sensor_error'
        
        return jsonify({
            'status': status,
            'timestamp': datetime.now().isoformat(),
            'sensor_responsive': test_distance is not None
        })
    except Exception as e:
        return jsonify({
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500

@app.route('/config')
def get_config():
    """Get sensor configuration"""
    return jsonify({
        'trigger_pin': sensor.trigger_pin,
        'echo_pin': sensor.echo_pin,
        'measurement_unit': 'centimeters',
        'update_interval': 'on_demand'
    })

def continuous_reading():
    """Background thread for continuous sensor readings"""
    while True:
        try:
            sensor.update_reading()
            time.sleep(1)  # Update every second
        except Exception as e:
            logger.error(f"Error in continuous reading: {e}")
            time.sleep(5)  # Wait longer on error

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({
        'success': False,
        'error': 'Endpoint not found'
    }), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({
        'success': False,
        'error': 'Internal server error'
    }), 500

if __name__ == '__main__':
    try:
        # Start background reading thread
        reading_thread = Thread(target=continuous_reading, daemon=True)
        reading_thread.start()
        logger.info("Background reading thread started")
        
        # Start Flask server
        logger.info("Starting Ultrasonic Sensor API Server...")
        app.run(host='0.0.0.0', port=5000, debug=False)
        
    except KeyboardInterrupt:
        logger.info("Shutting down server...")
    except Exception as e:
        logger.error(f"Server error: {e}")
    finally:
        sensor.cleanup()
        logger.info("GPIO cleaned up")