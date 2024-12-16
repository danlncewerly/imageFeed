import Foundation
final class ImagesListService {
    
    private(set) var photos: [Photo] = []
    private var task: URLSessionTask?
    private var lastLoadedPage = 1
    private lazy var dateFormatter = ISO8601DateFormatter()
    private var isRequestInProgress = false // Флаг для отслеживания текущего запроса

    static let shared = ImagesListService()
    static let didChangeNotification = Notification.Name(rawValue: "ImagesListServiceProviderDidChange")

    
    func fetchPhotosNextPage(handler: @escaping (Result<[PhotoResult], any Error>) -> Void) {
        if isRequestInProgress {
            print("Запрос уже выполняется. Пожалуйста, подождите.")
            return
        }
        isRequestInProgress = true

        guard let photoRequest = makePhotoRequest(page: lastLoadedPage) else {
            print("Ошибка подготовки запроса для фото")
            isRequestInProgress = false
            return
        }

        let task = URLSession.shared.objectTask(for: photoRequest) { [weak self] (result: Result<[PhotoResult], Error>) in
            guard let self else { return }
            self.isRequestInProgress = false // Запрос завершен, сбрасываем флаг
            
            switch result {
            case .success(let data):
                for i in data {
                    // Если createdAt равно nil, просто пропускаем этот объект
                    guard let createdAtData = i.createdAt else {
                        print("Отсутствуют данные createdAt для фото с id: \(i.id). Пропускаем.")
                        continue // Переходим к следующей фотографии
                    }
                    
                    self.photos.append(Photo(id: i.id,
                                             size: CGSize(width: i.width, height: i.height),
                                             createdAt: self.dateFormatter.date(from: createdAtData),
                                             welcomeDescription: i.description,
                                             thumbImageURL: i.urls.thumb,
                                             largeImageURL: i.urls.full,
                                             isLiked: i.likedByUser))
                    print("Количество фотографий: \(self.photos.count)")
                    print("Последняя загруженная страница: \(self.lastLoadedPage)")
                }

                NotificationCenter.default.post(
                    name: ImagesListService.didChangeNotification,
                    object: self,
                    userInfo: ["Photo": data])
                
                handler(.success(data))
                self.lastLoadedPage += 1

            case .failure(let error):
                print("Ошибка при получении фото")
                handler(.failure(error))
            }
        }
        self.task = task
        task.resume()
    }
    
    func changeLike(photoId: String, isLike: Bool, _ completion: @escaping (Result<Bool, Error>) -> Void) {
        
        // Если запрос уже в процессе, не начинаем новый
        if isRequestInProgress {
            print("Запрос уже выполняется. Пожалуйста, подождите.")
            return
        }

        // Отмечаем, что запрос в процессе
        isRequestInProgress = true

        let oAuth2TokenStorage = OAuth2TokenStorage.shared
        guard
            let token = oAuth2TokenStorage.token,
            let baseURL = Constants.defaultBaseURL
        else {
            preconditionFailure("Не удалось получить базовый URL для ответа о лайке")
        }
        
        guard let url = URL(string: "/photos/\(photoId)/like", relativeTo: baseURL) else {
            preconditionFailure("Не удалось построить URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = isLike ? "POST" : "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        print("URL запроса для changeLike: \(request)")

        let task = URLSession.shared.objectTask(for: request) { [weak self] (result: Result<ChangeLike, Error>) in
            guard let self else { return }
            self.isRequestInProgress = false // Запрос завершен, сбрасываем флаг
            
            switch result {
            case .success(let photoLike):
                DispatchQueue.main.async {
                    let like = photoLike.photo
                    let likeResult = like.likedByUser
                    if let index = self.photos.firstIndex(where: { $0.id == photoId }) {
                        let photo = self.photos[index]
                        let newPhoto = Photo(id: photo.id,
                                             size: photo.size,
                                             createdAt: photo.createdAt,
                                             welcomeDescription: photo.welcomeDescription,
                                             thumbImageURL: photo.thumbImageURL,
                                             largeImageURL: photo.largeImageURL,
                                             isLiked: !photo.isLiked)
                        self.photos[index] = newPhoto
                        print("Массив photos после changeLike: \(self.photos[index])")
                    }
                    completion(.success(likeResult))
                    print("Результат лайка: \(likeResult)")
                }
            case .failure(_):
                print("Ошибка при изменении лайка")
            }
        }
        task.resume()
    }
    
    func ImagesListServicePhotosClean() {
        photos = []
        lastLoadedPage = 1
    }
}

// MARK: - Private Methods
private func makePhotoRequest(page: Int) -> URLRequest? {
    let oAuth2TokenStorage = OAuth2TokenStorage.shared
    guard
        let token = oAuth2TokenStorage.token,
        let baseURL = Constants.defaultBaseURL
    else {
        preconditionFailure("Не удалось получить токен или базовый URL")
    }
    
    guard let url = URL(string: "/photos?page=\(page)", relativeTo: baseURL) else {
        preconditionFailure("Не удалось построить URL для фото")
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    print("Запрос URL для фото: \(request)")
    return request
}

