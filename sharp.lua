--[[

		 ___         ___   ___   ___  
		|     |   | |   | |   | |   | 
		 -+-  |-+-| |-+-| |-+-  |-+-  
			| |   | |   | |  \  |     
		 ---    
		Ver. Alpha
		
		Copyright 2018, Alejandro Celis <t.me/aesthezel>
		Based on UNMAINTENED telegram-bot by Yogop <https://github.com/yagop/telegram-bot/>
		Read LICENSE for more details.
 
]]

-- REQUERIMIENTOS
HTTP = require('socket.http')
HTTPS = require('ssl.https')
URL = require('socket.url')
JSON = require('dkjson')
redis = require('redis')
clr = require 'term.colors'
db = Redis.connect('127.0.0.1', 6379)
db:select(1)
serpent = require('serpent')

local function check_config()
	if not config.bot_api_key or config.bot_api_key == '' then
		return 'No se ha encontrado el TOKEN del BOT, agregalo.'
	elseif not config.admin.owner or config.admin.owner == '' then
		return 'Debes ingresar el ID del creador del BOT. ¡Tendrá todo los permisos!'
	elseif not config.bot_settings.cache_time.adminlist or config.bot_settings.cache_time.adminlist == '' then
		return 'Agrega el cache para actualizar la lista de administradores de grupos.'
	end
end

function sharp_start(on_reload) -- Funcion que inicia todo. ###(bot_init)
	config = dofile('alma.lua') -- Archivo de configuración.
	local error = check_config()
	if error then
		print(clr.red..error)
		return
	end
	print(clr.blue..'Leyendo lista de baneos globales...' ..clr.reset)
	foxbans = dofile('datos/expulsiones.lua') -- Analiza la lista de expulsiones globales. ###(gbans)
	misc, roles = dofile('codex.lua') -- Carga todas las funciones del BOT.
	lang = dofile(config.languages) -- Analiza los lenguajes disponibles.
	key = dofile("claves.lua") -- Lee las claves privadas de otras API, Ej: Google API.
	api = require('pensamiento') -- El archivo de funciones de la API de Telegram.
	
	current_m = 0
	last_m = 0
	
	bot = nil
	while not bot do -- Chequea si la información es correcta, si no lo es regresa un valor inválido.
		bot = api.getMe()
	end
	bot = bot.result

	plugins = {} -- Funcion, sistema de plugins.
	for i,v in ipairs(config.plugins) do
		local p = dofile('agregados/'..v)
		table.insert(plugins, p)
	end
	if config.bot_settings.multipurpose_mode then
		for i,v in ipairs(config.multipurpose_plugins) do
			local p = dofile('agregados/extra/'..v)
			table.insert(plugins, p)
		end
	end

	print('\n'..clr.blue..'BOT EJECUTANDOSE:'..clr.reset, clr.red..'[@'..bot.username .. '] [' .. bot.first_name ..'] ['..bot.id..']'..clr.reset..'\n')
	if not on_reload then
		db:hincrby('bot:general', 'starts', 1)
		api.sendAdmin('*Sharp aka. Jack*\nIniciado nuevamente\n_'..os.date('%A, %d %B %Y\n%X')..'_\n'..#plugins..' agregados cargados', true)
	end
	
	-- Genera un valor aleatorio y utiliza el primer número aleatorio.
	math.randomseed(os.time())
	math.random()

	last_update = last_update or 0 		-- Estalece una variable de bucle, para compenzar el tiempo,
	last_cron = last_cron or os.time() 	-- la hora del último "cron job".
	is_started = true 					-- si el BOT debería estar ejecutándose o no.
	
	if on_reload then return #plugins end

end

local function get_from(msg) -- Lectura de mensajes en consola.
	local user = '['..msg.from.first_name
	if msg.from.last_name then
		user = user..' '..msg.from.last_name
	end
	user = user..']'
	if msg.from.username then
		user = user..' [@'..msg.from.username..']'
	end
	user = user..' ['..msg.from.id..']'
	return user
end

local function get_what(msg) -- Identificador de formato de multimedia.
	if msg.sticker then
		return 'sticker'
	elseif msg.photo then
		return 'photo'
	elseif msg.document then
		return 'document'
	elseif msg.audio then
		return 'audio'
	elseif msg.video then
		return 'video'
	elseif msg.voice then
		return 'voice'
	elseif msg.contact then
		return 'contact'
	elseif msg.location then
		return 'location'
	elseif msg.text then
		return 'text'
	else
		return 'service message'
	end
end

local function collect_stats(msg)
	
	-- Contador de mensajes recibidos por el BOT -> Redis.
	db:hincrby('bot:general', 'messages', 1)
	
	-- Resolvedor de nombre de usuarios.
	if msg.from and msg.from.username then
		db:hset('bot:usernames', '@'..msg.from.username:lower(), msg.from.id)
		db:hset('bot:usernames:'..msg.chat.id, '@'..msg.from.username:lower(), msg.from.id)
	end
	if msg.forward_from and msg.forward_from.username then -- Resolvedor de respuestas.
		db:hset('bot:usernames', '@'..msg.forward_from.username:lower(), msg.forward_from.id)
		db:hset('bot:usernames:'..msg.chat.id, '@'..msg.forward_from.username:lower(), msg.forward_from.id)
	end
	
	if not(msg.chat.type == 'private') then
		if msg.from then
			db:hset('chat:'..msg.chat.id..':userlast', msg.from.id, os.time()) -- Último mensaje de usuarios.
			db:hset('bot:chat:latsmsg', msg.chat.id, os.time()) -- Último mensaje de grupo.
		end
	end
	
	-- Estadísticas de usuarios.
	if msg.from then
		db:hincrby('user:'..msg.from.id, 'msgs', 1)
	end
end

local function match_pattern(pattern, text)
  	if text then
  		text = text:gsub('@'..bot.username, '')
    	local matches = {}
    	if pattern[1] then
    		for match in string.gmatch(text, pattern[1]) do
    			if match ~= "" or match ~= nil then
    				matches[#matches+1] = match
    			end
    		end
    		if next(matches) then
    			return matches
    		end
    	else
    		matches = { string.match(text, pattern) }
    		if next(matches) then
    			return matches
			end
    	end
  	end
end

on_msg_receive = function(msg) -- El función se ejecuta cada vez que se recibe un mensaje.
	--vardump(msg) ### No implementado aún.
	if not msg then
		api.sendAdmin('Retorno sin mensajes') return
	end
	
	if msg.date < os.time() - 7 then return end -- No procesará viejos mensajes.
	if not msg.text then msg.text = msg.caption or '' end
	
	msg.normal_group = false
	if msg.chat.type == 'group' then msg.normal_group = true end
	
	-- Registro de lenguaje -> Redis.
	msg.ln = (db:get('lang:'..msg.chat.id)) or 'es'
	
	collect_stats(msg) -- ###resolve_username, crea la estadistica.
	
	local stop_loop
	for i, plugin in pairs(plugins) do
		if plugin.on_each_msg then
			msg, stop_loop = plugin.on_each_msg(msg, msg.lang)
		end
		if stop_loop then -- Detiene cualquier loop de una función agregada.
			return
		end
	end
	
	for i,plugin in pairs(plugins) do
		if plugin.triggers then
			if (config.bot_settings.testing_mode and plugin.test) or not plugin.test then -- Switch: si la función TEST está habilitada cargará agregados de prueba.
				for k,w in pairs(plugin.triggers) do				
					local blocks = match_pattern(w, msg.text)
					if w[1] then w = w[1] end
					if blocks then
						
						-- NUEVO / 0.5.0 -- Funcionaes para el NICKNAME.
						msg.chat.id_str = tostring(msg.chat.id)
						msg.from.id_str = tostring(msg.from.id)
						
						-- Solución temporal del bug de chat privado.
						if not(msg.chat.type == 'private') and not db:exists('chat:'..msg.chat.id..':settings') and not msg.service then
							misc.initGroup(msg.chat.id)
						end
						
						-- Muestra las acciones hechas por usuarios en la terminal.
						print(clr.reset..clr.blue..'['..os.date('%X')..']'..clr.red..' '..w..clr.reset..' '..get_from(msg)..' -> ['..msg.chat.id..'] ['..msg.chat.type..']')
						
						-- ||
						if blocks[1] ~= '' then
      						db:hincrby('bot:general', 'query', 1)
      						if msg.from then db:incrby('user:'..msg.from.id..':query', 1) end
      					end
						
						-- Ejecuta al función de algún agregado.
						local success, result = pcall(function()
							return plugin.action(msg, blocks)
						end)
						
						-- Si se detecta una mal función, replicará con un aviso de BUG.
						if not success then
							print(msg.text, result)
							if config.bot_settings.notify_bug then
								api.sendReply(msg, '*Se ha detectado un BUG*', true)
							end
							--misc.save_log('errors', result, msg.from.id or false, msg.chat.id or false, msg.text or false) ### No implementado aún.
          					api.sendAdmin('Un #error a ocurrido.\n'..result..'\n'..msg.ln..'\n'..msg.text)
							return
						end
						
						-- Si la acción devuelve una tabla, el resultado será una tabla.
						if type(result) == 'table' then
							msg = result
						elseif type(result) == 'string' then
							msg.text = result
						-- Si la acción es válida, la acepta.
						elseif result ~= true then
							return
						end
					end
				end
			end
		end
	end
end

local function service_to_message(msg)
	msg.service = true
	if msg.new_chat_member then
    	if tonumber(msg.new_chat_member.id) == tonumber(bot.id) then
			msg.text = '###addedongroup' -- Mensaje que dará cuando sea agregado en un grupo.
		else
			msg.text = '###added' -- Usuario agregado al grupo en precensia del BOT.
		end
		msg.adder = misc.clone_table(msg.from)
		msg.added = misc.clone_table(msg.new_chat_member)
	elseif msg.left_chat_member then
    	if tonumber(msg.left_chat_member.id) == tonumber(bot.id) then
			msg.text = '###removedfromgroup' -- Mensaje que dará cuando sea agregado en un grupo.
		else
			msg.text = '###removed' -- Usuario removido al grupo en precensia del BOT.
		end
		msg.remover = misc.clone_table(msg.from)
		msg.removed = misc.clone_table(msg.left_chat_member)
	elseif msg.group_chat_created then
    	msg.chat_created = true
    	msg.adder = misc.clone_table(msg.from)
    	msg.text = '###addedongroup' -- Clonación de mensaje  en caso de ser removido posteriormente.
	end
    return on_msg_receive(msg)
end

local function forward_to_msg(msg) -- Función de respuesta.
	if msg.text then
		msg.text = '###forward:'..msg.text
	else
		msg.text = '###forward'
	end
    return on_msg_receive(msg)
end

local function media_to_msg(msg)
	msg.media = true
	if msg.photo then
		msg.text = '###image'
		msg.media_type = 'image'
		--if msg.caption then
			--msg.text = msg.text..':'..msg.caption ### No implementado aún, error con la actualización de API.
		--end
	elseif msg.video then
		msg.text = '###video'
		msg.media_type = 'video'
	elseif msg.audio then
		msg.text = '###audio'
		msg.media_type = 'audio'
	elseif msg.voice then
		msg.text = '###voice'
		msg.media_type = 'voice'
	elseif msg.document then
		msg.text = '###file'
		msg.media_type = 'file'
		if msg.document.mime_type == 'video/mp4' then
			msg.text = '###gif'
			msg.media_type = 'gif'
		end
	elseif msg.sticker then
		msg.text = '###sticker'
		msg.media_type = 'sticker'
	elseif msg.contact then
		msg.text = '###contact'
		msg.media_type = 'contact'
	else
		msg.media = false
	end
	
	-- Chequeo de enlaces provenientes de Telegram.
	if msg.entities then
		for i,entity in pairs(msg.entities) do
			if entity.type == 'text_mention' then
				msg.mention_id = entity.user.id
			end
			if entity.type == 'url' or entity.type == 'text_link' then
				if msg.text:match('[Tt][Ee][Ll][Ee][Gg][Rr][Aa][Mm]%.[Mm][Ee]' or '[Tt]%.[Mm][Ee]') then -- Agregado el nuevo dominio corto "t.me".
					msg.media_type = 'TGlink'
				else
					msg.media_type = 'link'
				end
				msg.media = true
			end
		end
	end
	
	if msg.reply_to_message then
		msg.reply = msg.reply_to_message
	end
	return on_msg_receive(msg)
end

local function rethink_reply(msg)
	msg.reply = msg.reply_to_message
	if msg.reply.caption then
		msg.reply.text = msg.reply.caption
	end
	return on_msg_receive(msg)
end

local function handle_inline_keyboards_cb(msg)
	msg.text = '###cb:'..msg.data
	msg.old_text = msg.message.text
	msg.old_date = msg.message.date
	msg.date = os.time()
	msg.cb = true
	msg.cb_id = msg.id
	--msg.cb_table = JSON.decode(msg.data) ### No implementado aún.
	msg.message_id = msg.message.message_id
	msg.chat = msg.message.chat
	msg.message = nil
	msg.target_id = msg.data:match('(-?%d+)$')
	return on_msg_receive(msg)
end

-- PRIMERA FUNCIÓN: Esta es la que ejecutará al ser iniciado por el terminal.

sharp_start() -- Inicia el BOT.

while is_started do -- El loop que hará saber si el BOT debe permanecer activo.
	local res = api.getUpdates(last_update+1) -- Se mantiene actualizado de cualquier función paralela.
	if res then
		--vardump(res) ### No implementado aún.
		for i,msg in ipairs(res.result) do -- Repasa cada nuevo mensaje.
			last_update = msg.update_id
			current_m = current_m + 1
			if msg.message  or msg.callback_query --[[or msg.edited_message]]then
				--[[if msg.edited_message then
					msg.message = msg.edited_message
					msg.edited_message = nil
				end]]
				if msg.callback_query then
					handle_inline_keyboards_cb(msg.callback_query)
				elseif msg.message.migrate_to_chat_id then
					misc.to_supergroup(msg.message)
				elseif msg.message.new_chat_member or msg.message.left_chat_member or msg.message.group_chat_created then
					service_to_message(msg.message)
				elseif msg.message.photo or msg.message.video or msg.message.document or msg.message.voice or msg.message.audio or msg.message.sticker or msg.message.entities then
					media_to_msg(msg.message)
				elseif msg.message.forward_from then
					forward_to_msg(msg.message)
				elseif msg.message.reply_to_message then
					rethink_reply(msg.message)
				else
					on_msg_receive(msg.message)
				end
			end
		end
	else
		print('Error de conexión')
	end
	if last_cron ~= os.date('%M') then -- Ejecuta "cron jobs" cada minuto.
		last_cron = os.date('%M')
		last_m = current_m
		current_m = 0
		for i,v in ipairs(plugins) do
			if v.cron then -- Llama la función "cron" de cada agregado, si es que tiene una.
				local res, err = pcall(function() v.cron() end)
				if not res then
          			api.sendLog('Un #error a ocurrido.\n'..err) -- Si falla un "cron job".
					return
				end
			end
		end
	end
end

print('El BOT se está apagando.\n') -- FIN
