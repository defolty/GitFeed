/// Copyright (c) 2020 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// This project and source code may use libraries or frameworks that are
/// released under various Open-Source licenses. Use of those libraries and
/// frameworks are governed by their own individual licenses.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import RxSwift
import RxCocoa
import Kingfisher

func cachedFileURL(_ fileName: String) -> URL {
  return FileManager.default
    .urls(for: .cachesDirectory, in: .allDomainsMask)
    .first!
    .appendingPathComponent(fileName)
}

class ActivityController: UITableViewController {
  
  ///# это URL файла, где мы будем хранить файл событий на диске нашего устройства.
  ///# ниже реализуем функцию cachedFileURL, чтобы получить URL, по которому можно читать и записывать файлы
  private let eventsFileURL = cachedFileURL("events.json")
  
  private let repo = "ReactiveX/RxSwift"
  
  private let events = BehaviorRelay<[Event]>(value: [])
  private let disposeBag = DisposeBag()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    title = repo
    
    self.refreshControl = UIRefreshControl()
    let refreshControl = self.refreshControl!
    
    refreshControl.backgroundColor = UIColor(white: 0.98, alpha: 1.0)
    refreshControl.tintColor = UIColor.darkGray
    refreshControl.attributedTitle = NSAttributedString(string: "Pull to refresh")
    refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
     
    loadDataFromDisk()
    refresh()
  }
  
  @objc func refresh() {
    DispatchQueue.global(qos: .default).async { [weak self] in
      guard let self = self else { return }
      self.fetchEvents(repo: self.repo)
    }
  }
  
  private func loadDataFromDisk() {
    ///# сначала считываем данные хранилища с диска;
    ///# затем создаём `JSONDecoder` и пытаемся декодировать данные обратно в массив событий.
    ///# добавляем массив событий в реестр событий, используя его метод `accept`, или пустой массив при ошибке;
    ///# поскольку мы сохраняли события на диск, все они должны быть действительными, но - безопасность превыше всего!
    let decoder = JSONDecoder()
    if let eventsData = try? Data(contentsOf: eventsFileURL),
       let persistentEvents = try? decoder.decode([Event].self, from: eventsData) {
      events.accept(persistentEvents)
    }
  }
  
  func fetchEvents(repo: String) {
    let response = Observable.from([repo])
      .map { urlString -> URL in
        return URL(string: "https://api.github.com/repos/\(urlString)/events")!
      }
      .map { url -> URLRequest in
        return URLRequest(url: url)
      }
      .flatMap { request -> Observable<(response: HTTPURLResponse, data: Data)> in
        ///# `URLSession.rx.response(request:)` отправляет ваш запрос на сервер,
        ///# а после получения ответа испускает событие `.next` только один раз с возвращенными данными, а затем завершает работу.
        return URLSession.shared.rx.response(request: request)
      }
      ///# чтобы поделиться наблюдаемой и сохранить в буфере последнее испущенное событие
      .share(replay: 1)
      ///# эмпирическое правило использования `share(replay:scope:)` заключается в том,
      ///# чтобы использовать его для любых последовательностей, которые вы ожидаете завершить, или последовательностей,
      ///# которые вызывают большую нагрузку и на которые подписываются несколько раз
    
    response
      ///# c помощью `.filter` отбрасываем все коды ответов с ошибками.
      ///# `.filter` будет пропускать только ответы с кодом состояния между 200 и 300, то есть все коды состояния .success
      .filter { response, _ in
        return 200..<300 ~= response.statusCode /// `~=` который при использовании с диапазоном в левой части проверяет, включает ли диапазон значение в правой части.
      }
    
      ///# `compactMap` - пропускаем любые значения без nil и фильтруем любые nil
      ///# отбрасываем объект ответа и берём только данные ответа.
      .compactMap { _, data -> [Event]? in
        ///# создаём `JSONDecoder` и пытаемся декодировать данные ответа как массив `Events`
        ///# `try?` для возврата значения `nil` в случае, если декодер выдает ошибку при декодировании данных `JSON`
        return try? JSONDecoder().decode([Event].self, from: data)
      }
    
      .subscribe(onNext: { [weak self] newEvents in
        self?.processEvents(newEvents)
      })
    
      .disposed(by: disposeBag)
  }
  
  func processEvents(_ newEvents: [Event]) {
    var updatedEvents = newEvents + events.value
    if updatedEvents.count > 50 { // ограничение списка 50-ю объектами
      updatedEvents = [Event](updatedEvents.prefix(upTo: 50))
      
      let encoder = JSONEncoder()
      if let eventsData = try? encoder.encode(updatedEvents) {
        try? eventsData.write(to: eventsFileURL, options: .atomicWrite)
      }
    }
    
    events.accept(updatedEvents)
    DispatchQueue.main.async {
      self.tableView.reloadData()
      self.refreshControl?.endRefreshing()
    }
  }
  
  // MARK: - Table Data Source
  
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return events.value.count
  }
  
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let event = events.value[indexPath.row]
    
    let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!
    cell.textLabel?.text = event.actor.name
    cell.detailTextLabel?.text = event.repo.name + ", " + event.action.replacingOccurrences(of: "Event", with: "").lowercased()
    cell.imageView?.kf.setImage(with: event.actor.avatar, placeholder: UIImage(named: "blank-avatar"))
    return cell
  }
}
