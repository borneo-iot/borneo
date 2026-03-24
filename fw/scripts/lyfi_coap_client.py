import logging
import asyncio
import struct
from cbor2 import dumps, loads

from aiocoap import *

logging.basicConfig(level=logging.INFO)


class BorneoError(RuntimeError):
    pass


class AbstractBorneoDeviceCoapClient:
    def __init__(self, address):
        self.address = address

    async def open(self):
        self._context = await Context.create_client_context()

    async def close(self):
        await self._context.shutdown()

    async def __aenter__(self):
        await self.open()
        return self

    async def __aexit__(self, exc_type, exc, tb):
        await self.close()

    async def get_wellknown_core(self):
        uri = self.address + '/.well-known/core'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return response.payload

    async def factory_reset(self):
        uri = self.address + '/borneo/v1/factory/reset'
        msg = Message(code=POST, uri=uri, mtype=NON, no_response=26)
        await self._context.request(msg).response

    async def factory_set_name(self, name: str):
        uri = self.address + '/borneo/v1/factory/name'
        payload = dumps(name)
        msg = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(msg).response

    async def factory_set_model(self, model: str):
        uri = self.address + '/borneo/v1/factory/name'
        payload = dumps(model)
        msg = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(msg).response

    async def factory_set_vendor(self, vendor: str):
        uri = self.address + '/borneo/v1/factory/name'
        payload = dumps(vendor)
        msg = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(msg).response

    async def reboot(self):
        uri = self.address + '/borneo/v1/reboot'
        msg = Message(code=POST, uri=uri, mtype=NON, no_response=26)
        await self._context.request(msg).response

    async def get_info(self):
        uri = self.address + '/borneo/v1/info'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def get_timezone(self):
        uri = self.address + '/borneo/v1/settings/timezone'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def set_timezone(self, tz: str):
        uri = self.address + '/borneo/v1/settings/timezone'
        payload = dumps(tz)
        request = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(request).response

    async def get_upgrade_new_version(self):
        uri = self.address + '/borneo/v1/upgrade/new-version'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def get_upgrade_checking(self):
        uri = self.address + '/borneo/v1/upgrade/checking'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def set_upgrade_checking(self):
        uri = self.address + '/borneo/v1/upgrade/checking'
        payload = dumps(True)
        request = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(request).response

    async def is_upgrading(self):
        uri = self.address + '/borneo/v1/upgrade/upgrading'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def begin_upgrade(self):
        uri = self.address + '/borneo/v1/upgrade/upgrading'
        payload = dumps(True)
        request = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(request).response

    async def get_status(self):
        uri = self.address + '/borneo/v1/status'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)


class LyfiDeviceCoapClient(AbstractBorneoDeviceCoapClient):

    async def get_lyfi_info(self):
        uri = self.address + '/borneo/lyfi/v1/info'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def get_lyfi_status(self):
        uri = self.address + '/borneo/lyfi/v1/status'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def get_color(self):
        uri = self.address + '/borneo/lyfi/v1/color'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def set_color(self, color):
        uri = self.address + '/borneo/lyfi/v1/color'
        payload = dumps(color)
        request = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(request).response

    async def get_schedule(self):
        uri = self.address + '/borneo/lyfi/v1/schedule'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def set_schedule(self, schedule):
        uri = self.address + '/borneo/lyfi/v1/schedule'
        payload = dumps(schedule)
        request = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(request).response

    async def get_current_mode(self) -> int:
        uri = self.address + '/borneo/lyfi/v1/mode'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)

    async def set_current_mode(self, mode: int):
        uri = self.address + '/borneo/lyfi/v1/mode'
        payload = dumps(mode)
        request = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(request).response

    async def set_fan_power(self, power: int):
        uri = self.address + '/borneo/lyfi/v1/fan/power'
        payload = dumps(power)
        request = Message(code=PUT, payload=payload, uri=uri)
        await self._context.request(request).response

    async def set_keep_temp(self, kp: int):
        uri = self.address + '/borneo/lyfi/v1/thermal/temp/keep'
        payload = dumps(kp)
        request = Message(code=PUT, payload=payload, uri=uri)
        response = await self._context.request(request).response

    async def get_keep_temp(self) -> int:
        uri = self.address + '/borneo/lyfi/v1/thermal/temp/keep'
        request = Message(code=GET, uri=uri)
        response = await self._context.request(request).response
        return loads(response.payload)
