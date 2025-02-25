# Jivo SDK API: Native



### Содержание

- [Пространство имён **JivoSDK.session**](#namespace_session)
    - *var delegate*
    - *func setPreferredServer(_:)*
    - *func startUp(channelID:userToken:)*
    - *func setClientInfo(_:)*
    - *func setCustomData(fields:)*
    - *func shutDown()*
    - *protocol JivoSDKSessionDelegate*
    - *struct JivoSDKSessionClientInfo*
    - *struct JivoSDKSessionCustomDataField*
- [Пространство имён **JivoSDK.chattingUI**](#namespace_chattingUI)
    - *var delegate*
    - *var isDisplaying*
    - *func push(into:)*
    - *func push(into:config:)*
    - *func place(within:)*
    - *func place(within:closeButton:config:)*
    - *func present(over:)*
    - *func present(over:config:)*
    - *protocol JivoSDKChattingUIDelegate*
    - *struct JivoSDKChattingConfig*
- [Пространство имён **JivoSDK.notifications**](#namespace_notifications)
    - *func setPermissionAsking(at:handler:)*
    - *func setPushToken(data:)*
    - *func setPushToken(hex:)*
    - *func handleRemoteNotification(userInfo:)*
    - *func handleNotification(_:)*
    - *func handleNotification(response:)*
- [Пространство имён **JivoSDK.debugging**](#namespace_debugging)
    - *var level*
    - *func archiveLogs(completion:)* 
    - *enum JivoSDKDebuggingLevel*
    - *enum JivoSDKArchivingStatus*



### Пространство имён <a name="namespace_session">JivoSDK.session</a>

<a name="vtable:JivoSDK.session.delegate" />

```swift
var delegate: JivoSDKSessionDelegate? { get set }
```

Делегат для обработки событий, связанных с соединением и сессией клиента (подробнее [здесь](#type_JivoSDKSessionDelegate)).
> На данный момент протокол JivoSDKSessionDelegate не содержит ни одного объявления внутри себя. Поделитесь с нами, какие свойства или методы обратного вызова вы бы хотели увидеть в нём.

<a name="vtable:JivoSDK.session.delegate" />


```swift
func setPreferredServer(_ server: JivoSDKSessionServer)
```

Устанавливает предпочтительный сервер для соединения SDK с серверами **Jivo**.

- `server: JivoSDKSessionServer`

    Предпочтительная региональная привязка сервера:

    - `europe`
        Европейские сервера
    - `russia`
        Российские сервера
    - `asia`
        Азиатские сервера
    - `auto`
        Автоматический выбор

<a name="vtable:JivoSDK.session.startUp" />


```swift
func startUp(channelID: String, userToken: String)
```

Устанавливает соединение между SDK и нашими серверами, создавая новую сессию, либо возобновляя уже существующую.

- `channelID: String`

    Идентификатор вашего канала в **Jivo** (то же самое, что и `widget_id`);

- `userToken: String`

    Уникальная строка, идентифицирующая клиента чата, по которой определяется, требуется ли создать новую сессию с новым диалогом, либо восстановить уже существующую и загрузить историю начатого диалога. Генерируется на стороне интегратора **Jivo Mobile SDK**.

> Не вызывайте этот метод при отображённом на экране UI чата **Jivo Mobile SDK**.
>
> Если вам потребуется вызвать этот метод более одного раза, но с иным значением `userToken`, то перед повторным вызовом `startUp(...)` необходимо вызвать `shutDown()`.

Параметр `userToken` в последствии сохраняется в Keychain, поэтому восстановление сессии возможно и после удаления-переустановки приложения, и при смене девайса (при условии включенной синхронизации данных Keychain в iCloud).

Также, значение `userToken` передаётся в поле `"user_token"` тела запросов от [нашего Webhook API](https://www.jivo.ru/api/#webhooks).

<a name="vtable:JivoSDK.session.setClientInfo" />

```swift
func setClientInfo(_ info: JivoSDKSessionClientInfo?)
```

Задаёт дополнительную информацию о клиенте, которая отображается оператору.

- `info: JivoSDKSessionClientInfo?`

    Информация о клиенте (подробнее [здесь](#type_JivoSDKSessionClientInfo))

> На данный момент реализация метода такова, что для обновления дополнительной информации о клиенте на стороне оператора вам необходимо вызвать метод `JivoSDK.session.startUp(...)` после изменения Client Info.

<a name="vtable:JivoSDK.session.setCustomData" />

```swift
func setCustomData(fields: [JivoSDKSessionCustomDataField])
```

Задаёт дополнительную информацию о клиенте, которая отображается оператору.

- `fields: [JivoSDKSessionCustomDataField]`

    Дополнительная информация о клиенте (подробнее [здесь](#type_JivoSDKSessionClientInfo))

<a name="vtable:JivoSDK.session.shutDown" />

```swift
func shutDown()
```

Закрывает текущее соединение, производит очистку локальной базы данных и отправляет запрос на отписку устройства от PUSH-уведомлений для клиента сессии.

> Всегда вызывайте метод `shutDown()` перед тем, как повторно вызвать метод `startUp(channelID:userToken:)` с параметром `userToken`, отличным от того, что использовался в сессии ранее.



##### Вспомогательные типы

- Протокол <a name="type_JivoSDKSessionDelegate">**JivoSDKSessionDelegate**</a>

    Реализация появится в следующих версиях
    
- Структура <a name="type_JivoSDKSessionClientInfo">**JivoSDKSessionClientInfo**</a>

    - `name: String?`

        Имя клиента

    - `email: String?`

        E-mail клиента 

    - `phone: String?`

        Телефон клиента

    - `brief: String?`

        Дополнительная информация о клиенте в произвольной форме
    
- Структура <a name="type_JivoSDKSessionCustomDataField">**JivoSDKSessionCustomDataField**</a>

    - `title: String?`

    - `key: String?`

    - `content: String`

    - `link: String?`



### Пространство имён <a name="namespace_chattingUI">JivoSDK.chattingUI</a>



```swift
var delegate: JivoSDKChattingUIDelegate? { get set }
```

Устанавливает делегат для обработки событий, связанных с отображением UI чата на экране (подробнее [здесь](#type_JivoSDKChattingUIDelegate)).



```swift
var isDisplaying: Bool { get }
```

Возвращает `true`, если view объекта `UIViewController`, представляющего чат SDK, в данный момент находится в иерархии view (UI чата SDK в этом случае должен отображаться на экране), иначе – `false`.



```swift
func push(into navigationController: UINavigationController)
```

Добавляет `ViewController` чата **Jivo Mobile SDK** в стек переданного `UINavigationController` и отображает чат на экране с настройками UI по-умолчанию.

- `into navigationController: UINavigationController`

  Объект `UINavigationController`, в стек которого будет добавлен `ViewController`, отвечающий за UI чата. 



```swift
func push(into navigationController: UINavigationController, config: JivoSDKChattingConfig)
```

Добавляет `ViewController` чата **Jivo Mobile SDK** в стек переданного `UINavigationController` и отображает чат на экране с указанными настройками UI.

- `into navigationController: UINavigationController`

    Объект `UINavigationController`, в стек которого будет добавлен `ViewController`, отвечающий за UI чата

- `config: JivoSDKChattingConfig`
  
  Конфигурация UI чата (подробнее [здесь](#type_JivoSDKChattingConfig))



```swift
func place(within navigationController: UINavigationController)
```

Удаляет весь стек в переданном объекте `UINavigationController` и добавляет в стек `ViewController`, отвечающий за UI чата, с настройками отображения по умолчанию. 

- `within navigationController: UINavigationController`

  Объект `UINavigationController`, стек которого будет заменён на ViewController, отвечающий за UI чата.



```swift
func place(within navigationController: UINavigationController, closeButton: JivoSDKChattingCloseButton, config: JivoSDKChattingConfig) 
```

Удаляет весь стек в переданном объекте `UINavigationController` и добавляет в стек `ViewController`, отвечающий за UI чата, с заданными настройками отображения.

- `within navigationController: UINavigationController`

    Объект `UINavigationController`, стек которого будет заменён на `ViewController`, отвечающий за UI чата 
    
- `closeButton: JivoSDKChattingCloseButton`

    Выбор иконки для кнопки закрытия чата

- `config: JivoSDKChattingConfig`

  Конфигурация UI чата (подробнее [здесь](#type_JivoSDKChattingConfig))



```swift
func present(over viewController: UIViewController)
```

Отображает модально UI чата на экране с визуальными настройками по-умолчанию, вызывая метод `present(_:animated:)` для переданного `ViewController`. Выполняется анимировано.

- `over viewController: UIViewController`

  `ViewController`, поверх которого будет модально отображаться UI чата



```swift
func present(over viewController: UIViewController, config: JivoSDKChattingConfig)
```

Отображает модально UI чата на экране с заданными визуальными настройками, вызывая метод `present(_:animated:)` для переданного `ViewController`. Выполняется анимировано.

- `over viewController: UIViewController`

    `ViewController`, поверх которого будет модально отображаться UI чата
- `config: JivoSDKChattingConfig`

  Конфигурация UI чата (подробнее [здесь](#type_JivoSDKChattingConfig))



##### Вспомогательные типы



- Протокол <a name="type_JivoSDKChattingUIDelegate">**JivoSDKChattingUIDelegate**</a>

    - `func jivo(willAppear:)`
      
        Вызывается перед тем, как **Jivo Mobile SDK** откроется.
        
    - `func jivo(didDisappear:)`
      
        Вызывается после того, как **Jivo Mobile SDK** закрылся.
        
    - `func jivo(didRequestChattingUI:)`
      
        Вызывается, когда в соответствии с логикой работы **Jivo Mobile SDK** необходимо отобразить UI чата на экране.
        
        

- Структура <a name="type_JivoSDKChattingConfig">**JivoSDKChattingConfig**</a>

    - `locale: Locale?`

        Информация о регионе, по которой для UI чата устанавливается соответствующий язык (для локализации интерфейса доступны только те, языки, которые поддерживаются Jivo SDK). Значение по-умолчанию – `Locale.autoupdatingCurrent`

    - `useDefaultIcon: Bool` **[Только для Objective-C]**

        Указание, отображать ли иконку оператора по-умолчанию (изображение с логотипом Jivo). Если значение параметра – `true`, то иконка по-умолчанию будет отображена даже в случае указания `customIcon` или отсутствия аватара у оператора; если значение – `false`, то иконка по-умолчанию показана не будет и вместо неё отобразится либо изображение, переданное в параметре `customIcon`, либо аватар оператора при его подключении. При отсутствии `customIcon` и аватара никакое изображение в баре показано не будет, а тексты заголовка и подзаголовка сместятся влево, заполняя собой пустое место. Значение по-умолчанию – `true`

    - `customIcon: UIImage?` **[Только для Objective-C]**

        Кастомная иконка оператора до подключения, отображаемая в верхнем баре над окном чата, отображаемая в верхнем баре над окном чата. Если у оператора установлен аватар, то он заменяет собой иконку, переданную в параметре `customIcon`, иначе – `customIcon` продолжает оставаться на экране. Заменяется иконкой по-умолчанию, если значение `useDefaultIcon` равняется `true`. Значение по-умолчанию – `nil`;

    - `icon: JivoSDKTitleBarIconStyle?` **[Только для Swift]**

        Режим отображения иконки в верхнем баре над окном чата до подключения оператора. Принимает следующие значения типа `JivoSDKTitleBarIconStyle` (перечисление):

        - `default`

            Cтандартная иконка с логотипом Jivo

        - `hidden`

            Иконка не будет отображаться. Аватар оператора при наличии отобразится сразу после загрузки, при отсутствии – никакое изображение показано не будет, а тексты заголовка и подзаголовка сместятся влево, заполняя собой пустое место

        - `custom(UIImage)`

            Кастомное изображение, передаваемое в associated value кейса перечисления

    - `titlePlaceholder: String?`

        Текст заголовка , отображаемого в верхнем баре над окном чата, до того момента, как SDK не получит имя оператора (оно заменит собой текст `titlePlaceholder`)). Значение по-умолчанию – локализованная строка “Чат с поддержкой”

    - `titleColor: UIColor?`

        Цвет заголовка, отображаемого в верхнем баре над окном чата. Значение по-умолчанию – объект `UIColor`, содержащий чёрный/белый цвет (в зависимости от применённой темы)

    - `subtitleCaption: String?`

        Текст подзаголовка, отображаемого в верхнем баре над окном чата. Значение по-умолчанию – локализованная строка “На связи 24/7!”

    - `subtitleColor: UIColor?`

        Цвет подзаголовка, отображаемого в верхнем баре над окном чата. Значение по-умолчанию – объект `UIColor`, содержащий светло-серый цвет

    - `inputPlaceholder: String?`

        Плейсхолдер текстового поля ввода внизу окна чата. Значение по-умолчанию – локализованная строка “Введите ваше сообщение”

    - `inputPrefill: String?`

        Предварительно установленный в текстовое поле текст

    - `activeMessage: String?`

        Текст активного приглашения. Активное приглашение – это сообщение, которое автоматически отображается для новых клиентов в ленте чата слева. Если при инициализации для свойства передать `nil`, то активное приглашение показано не будет. Сообщение с активным приглашением отобразится только после того, как будет установлено соединение с сервером

    - `offlineMessage: String?`

        Текст оффлайн-сообщения. Оффлайн-сообщение – это сообщение, которое автоматически отображается после отправленного клиентом сообщения, если на канале нет активных операторов. Если для этого поля передать `nil` или пустой текст, то оффлайн-сообщение будет показано со стандартным текстом.
    
    - `outcomingPalette: JivoSDKChattingPaletteAlias?`
    
        Основной цвет для фона клиентских сообщений, кнопки отправки и каретки ввода текста. Возможные значения: `green` (по умолчанию), `blue`, `graphite`



### Пространство имён <a name="namespace_notifications">JivoSDK.notifications</a>

<a name="vtable:JivoSDK.notifications.delegate" />

```swift
var delegate: JivoSDKNotificationsDelegate? { get set }
```

Делегат для обработки событий, связанных с уведомлениями (подробнее [здесь](#type_JivoSDKNotificationsDelegate)).

<a name="vtable:JivoSDK.notifications.setPermissionAsking" />

```swift
func setPermissionAsking(at moment: JivoSDKNotificationsPermissionAskingMoment, handler: JivoSDKNotificationsPermissionAskingHandler)
```

Назначает момент, когда SDK должен запросить доступ к PUSH-уведомлениям, и определяет, какая подсистема должна заниматься обработкой входящих PUSH-событий.

- `at moment: JivoSDKNotificationsPermissionAskingMoment`
  
    Момент запроса доступа к PUSH уведомлениям
- `handler: JivoSDKNotificationsPermissionAskingHandler`
  
    Обработчик событий подсистемы PUSH

Следует вызывать до `JivoSDK.session.startUp(...)`

<a name="vtable:JivoSDK.notifications.setPushTokenData" />

```swift
func setPushToken(data: Data?)
```

Передаёт в SDK PUSH-токен устройства в видe `Data?`, ассоциируя его с клиентом сессии.

Когда PUSH-токен устройства попадает в SDK, он ассоциируется с конкретным клиентом (который был или будет определён параметром `userToken` метода `startUp(channelID:userToken:)`) и отправляется на сервер **Jivo**. После того, как сервер получает токен, у него появляется возможность отправлять PUSH-уведомления на устройство.

Если PUSH-токен устройства был задан до вызова метода 
`startUp(channelID:userToken:)`, то он сохраняется в SDK и будет отправлен на сервер **Jivo** после установления соединения. В случае, если PUSH-токен был установлен после вызова метода `startUp(channelID:userToken:)`, токен будет отправлен немедленно.

Для того, чтобы отписать устройство от PUSH уведомлений для текущего клиента, вызовите метод `shutDown()`.

<a name="vtable:JivoSDK.notifications.setPushTokenHex" />

```swift
func setPushToken(hex: String?)
```

Передаёт PUSH-токен устройства в SDK в виде `String?`, ассоциируя его с клиентом сессии.

Когда PUSH-токен устройства попадает в SDK, он ассоциируется с конкретным клиентом (который был или будет определён параметром `userToken` метода `JivoSDK.session.startUp(...)`) и отправляется на сервер **Jivo**. После того, как сервер получает токен, у него появляется возможность отправлять PUSH-уведомления на устройство.

Если PUSH-токен устройства был задан до вызова метода 
`JivoSDK.session.startUp(...)`, то он сохраняется в SDK и будет отправлен на сервер **Jivo** после установления соединения. В случае, если PUSH-токен был установлен после вызова метода `JivoSDK.session.startUp(...)`, токен будет отправлен немедленно.

Для того, чтобы отписать устройство от PUSH уведомлений для текущего клиента, вызовите метод `shutDown()`. 

> PUSH-токен не сохраняется в SDK между запусками приложения, поэтому вызывать этот метод нужно каждый раз, в том числе при переавторизации

<a name="vtable:JivoSDK.notifications.handleRemoteNotification" />

```swift
func handleRemoteNotification(userInfo: [AnyHashable : Any]) -> Bool
```
> Используйте этот метод, если вы обрабатываете PUSH-уведомления с помощью метода `UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` и не используете для этого методы фреймворка `UserNotifications`.

Обрабатывает данные PUSH-уведомления, передаваемые в параметре типа `[AnyHashable : Any]`, и возвращает `true`, если уведомление было отправлено со стороны **Jivo**, либо `false`, если уведомление было отправлено другой системой.

В рамках реализации этого метода **Jivo Mobile SDK** определяет тип уведомления от нашей системы. Если этот тип подразумевает, что нажатие пользователя на PUSH должно сопровождаться открытием экрана чата, то у `JivoSDKChattingUI.delegate` будет вызван метод `jivo(didRequestChattingUI:)`, запрашивающий от вас отображение UI чата SDK на экране.

- `containingUserInfo userInfo: [AnyHashable : Any]`

  Cловарь с данными из тела PUSH-уведомления.

> Метод предназначен для того, чтобы передавать в него приходящие PUSH-уведомления



```swift
func handleNotification(_ notification: UNNotification) -> Bool
```

> Используйте этот метод, если вы обрабатываете PUSH-уведомления с помощью методов фреймворка `UserNotifications`.
>
> Вызывайте этот метод при срабатывании реализованного вами метода `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:)` из фреймворка `UserNotifications`.

Обрабатывает данные PUSH-уведомления, передаваемые в параметре типа `UNNotification`, и возвращает `true`, если уведомление было отправлено со стороны **Jivo**, либо `false`, если уведомление было отправлено другой системой.

- `notification: UNNotification`

  Объект входящего уведомления.



```swift
func handleNotification(response: UNNotificationResponse) -> Bool
```

> Используйте этот метод, если вы обрабатываете PUSH-уведомления с помощью методов фреймворка `UserNotifications`.
>
> Вызывайте этот метод при срабатывании реализованного вами метода `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:)` из фреймворка `UserNotifications`.

Обрабатывает данные PUSH-уведомления при пользовательском взаимодействии с ним и возвращает `true`, если уведомление было отправлено со стороны **Jivo**, либо `false`, если уведомление было отправлено другой системой.

В рамках реализации этого метода **Jivo Mobile SDK** определяет тип уведомления от нашей системы. Если этот тип подразумевает, что нажатие пользователя на PUSH должно сопровождаться открытием экрана чата, то у `JivoSDKChattingUI.delegate` будет вызван метод `jivo(didRequestChattingUI:)`, запрашивающий от вас отображение UI чата SDK на экране.

- `response: UNNotificationResponse`

  Результат пользовательского взаимодействия с уведомлением.

> Метод предназначен для того, чтобы передавать в него приходящие PUSH-уведомления



##### Вспомогательные типы



- Протокол <a name="type_JivoSDKNotificationsDelegate">**JivoSDKNotificationsDelegate**</a>

    - `func jivo(needAccessToNotifications:proceedBlock:)`

        Вызывается перед тем, как **Jivo Mobile SDK** запросит доступ к Push-уведомлениям: можно использовать для отображения собственного UI, вызывая `proceedBlock()` по мере готовности к показу запроса разрешения.



### Пространство имён <a name="namespace_debugging">JivoSDK.debugging</a>



```swift
var level: JivoSDKDebuggingLevel { get set }
```

С помощью этого свойства вы можете задать степень того, насколько подробно будет производиться логирование в SDK (подробнее [здесь](#type_JivoSDKDebuggingLevel)).



```swift
func archiveLogs(completion: @escaping (URL?, JivoSDKArchivingStatus) -> Void)
```

Выполняет архивацию сохранённых записей логов и возвращает в completion-блоке ссылку на созданный архив и статус операции.

- `completion: @escaping (URL?, JivoSDKArchivingStatus) -> Void`

    Замыкание, которое будет вызвано по завершении операции. В блок будут переданы URL (если удалось создать архив) и статус результата операции (подробнее [здесь](#type_JivoSDKArchivingStatus)).

> Может выдавать пустой файл, если параметр `JivoSDK.debugging.level` был выставлен в значение `silent`



##### Вспомогательные типы



- Перечисление <a name="type_JivoSDKNotificationsPermissionAskingMoment">**JivoSDKNotificationsPermissionAskingMoment**</a>

    - `never`

      Никогда не запрашивать доступ к уведомлениям
    - `onConnect`

      Запрашивать доступ к уведомлениям, когда SDK подключается к серверам **Jivo** посредством вызова `JivoSDK.session.startUp(...)`
    - `onAppear`

      Запрашивать доступ к уведомлениям, когда происходит отображение окна SDK на экране
    - `onSend`
      
        Запрашивать доступ к уведомлениям, когда пользователь отправляет сообщение в диалог

- Перечисление <a name="type_JivoSDKNotificationsPermissionAskingHandler">**JivoSDKNotificationsPermissionAskingHandler**</a>

    - `sdk`
      
        Обрабатывать PUSH события должна подсистема SDK
    - `current`
      
        Обрабатывать PUSH события должна подсистема, которая на текущий момент для этого назначена
    
- Перечисление <a name="type_JivoSDKDebuggingLevel">**JivoSDKDebuggingLevel**</a>

    - `full`

        Режим полного логирования

    - `silent`

        Логирование не ведётся
        

- Перечисление <a name="type_JivoSDKArchivingStatus">**JivoSDKArchivingStatus**</a>

    - `success`

        Сохранённые записи логов были успешно заархивированы, параметр замыкания типа `URL?` содержит ссылку на созданный архив

    - `failedAccessing`

        Не удалось получить доступ к файлу архива в папке `Caches`, параметр замыкания типа `URL?` равен `nil`

    - `failedPreparing`

        Не удалось подготовить содержимое архива, возможна ошибка кодировки, параметр замыкания типа `URL?` равен `nil`
