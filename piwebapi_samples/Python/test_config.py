import configparser

config = configparser.ConfigParser()
config.read('test_config.ini')
PIWEBAPI_URL = config.get('Configuration', 'PIWEBAPI_URL')
AF_SERVER_NAME = config.get('Configuration', 'AF_SERVER_NAME')
PI_SERVER_NAME = config.get('Configuration', 'PI_SERVER_NAME')
USER_NAME = config.get('Configuartion', 'USER_NAME')
USER_PASSWORD = config.get('Configuration', 'USER_PASSWORD')
AUTH_TYPE = config.get('Configuration', 'AUTH_TYPE')
