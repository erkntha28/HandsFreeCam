📸 HandsFreeCam
"Kameranızı ellerinizi kullanmadan kontrol edin!"

HandsFreeCam, bilgisayarlı görü (Computer Vision) tekniklerini kullanarak kamera fonksiyonlarını el hareketleri, yüz jestleri veya ses komutları ile yönetmenizi sağlayan yenilikçi bir uygulamadır. Fotoğraf çekmek veya video kaydetmek için artık deklanşöre basmanıza gerek yok!

🌟 Öne Çıkan Özellikler
Hareket Algılama: Belirli el hareketleriyle (örneğin avuç içi gösterme veya zafer işareti) fotoğraf çekme.

Otomatik Zamanlayıcı: Elinizi kaldırdığınızda geri sayımı başlatan akıllı tetikleyiciler.

Arka Plan İşleme: Gerçek zamanlı görüntü analizi ile düşük gecikme süresi.

Kullanıcı Dostu Arayüz: Karmaşık ayarlara boğulmadan doğrudan kullanıma hazır yapı.

🛠️ Teknik Altyapı
Bu proje aşağıdaki temel kütüphaneler ve teknolojiler kullanılarak geliştirilmiştir:

Python: Ana programlama dili.

OpenCV: Görüntü işleme ve kamera yönetimi.

MediaPipe: El ve parmak takibi için Google'ın makine öğrenmesi çözümü.

NumPy: Matris işlemleri ve veri analizi.

🚀 Başlangıç
Gereksinimler
Sisteminizde Python 3.x ve bir web kamerası bulunmalıdır.

Kurulum
Depoyu klonlayın:

Bash

git clone https://github.com/erkntha28/HandsFreeCam.git
Gerekli kütüphaneleri yükleyin:

Bash

pip install opencv-python mediapipe numpy
Kullanım
Uygulamayı başlatmak için terminale şu komutu yazın:

Bash

python main.py
Ekranda elinizi gösterdiğinizde sistem hareketi tanıyacak ve tanımlı görevi (örneğin fotoğraf çekme) gerçekleştirecektir.

📂 Proje Mimarisi
Plaintext

├── models/           # Eğitilmiş modeller veya yapılandırma dosyaları
├── src/              # Algoritma ve görüntü işleme mantığı
├── output/           # Çekilen fotoğrafların kaydedildiği klasör
├── main.py           # Uygulama giriş noktası
└── requirements.txt  # Bağımlılık listesi
📸 Demo
(Buraya el hareketini yaparken çekilmiş bir GIF veya fotoğraf eklemek projenin etkileyiciliğini %100 artırır!)

🤝 Katkı Sağlayın
Bu projeyi daha ileriye taşımak için:

Projeyi Fork edin.

Yeni bir özellik dalı (Branch) oluşturun.

Değişikliklerinizi Commit edin.

Bir Pull Request gönderin.

📜 Lisans
Bu proje MIT lisansı ile korunmaktadır.
