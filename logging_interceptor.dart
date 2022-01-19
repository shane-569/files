import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dms_picklite/model/response_model/profile_response_model/profile_response_model.dart';
import 'package:dms_picklite/repository/app_repository.dart';
import 'package:dms_picklite/style/app_colors.dart';
import 'package:dms_picklite/widgets/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoggingInterceptor extends Interceptor {
  int _maxCharactersPerLine = 200;
  SharedPreferences? sharedPreferences;
  Dio? _dio;

  LoggingInterceptor(this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    print("--> ${options.method} ${options.path}");
    print("${options.headers}");
    print("Content type: ${options.contentType}");
    print("<-- END HTTP");
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print("<-- ${response.statusCode} ${response.data} ");
    String responseAsString = response.data.toString();
    if (responseAsString.length > _maxCharactersPerLine) {
      int iterations =
          (responseAsString.length / _maxCharactersPerLine).floor();
      for (int i = 0; i <= iterations; i++) {
        int endingIndex = i * _maxCharactersPerLine + _maxCharactersPerLine;
        if (endingIndex > responseAsString.length) {
          endingIndex = responseAsString.length;
        }
        print(
            responseAsString.substring(i * _maxCharactersPerLine, endingIndex));
      }
    } else {
      print(response.data);
    }
    print("<-- END HTTP");

    super.onResponse(response, handler);
  }

  @override
  void onError(DioError err, ErrorInterceptorHandler handler) async {
    print("error status" + err.toString());
    sharedPreferences = await SharedPreferences.getInstance();
    if (err is DioError) {
      if (err.error is SocketException) {
        AppToast.show("No Internet Found ", AppColors.red);
        super.onError(err, handler);
      }
    }
    if (err.response != null) {
      int responseCode = err.response!.statusCode!;
      print("<-- Error -->");
      print(err.error);
      print(err.message);
      print(err.response);
      // old code down
      // super.onError(err, handler);

      // new code copied
      var decodedData = jsonDecode(err.response.toString());
      if (responseCode == 401 &&
          decodedData["message"] != "Invalid Credentials") {
        _dio!.interceptors.requestLock.lock();
        _dio!.interceptors.responseLock.lock();

        Repository repository = Repository();
        ProfileResponseModel? profileResponseModel =
            await repository.getNewAccessToken();
        sharedPreferences!.clear();
        sharedPreferences!.setString(
            "access_token", profileResponseModel!.data!.token!.access!);
        sharedPreferences!.setString(
            "refresh_token", profileResponseModel.data!.token!.refresh!);

        RequestOptions requestOptions = err.requestOptions;
        Options options = Options(headers: {
          "Content-Type": "application/json",
          'Authorization':
              'Bearer ${sharedPreferences!.getString("access_token")}',
        });
        _dio!.interceptors.requestLock.unlock();
        _dio!.interceptors.responseLock.unlock();
        var response = await _dio!.request(requestOptions.path,
            data: requestOptions.data,
            queryParameters: requestOptions.queryParameters,
            options: options);

        handler.resolve(response);
      } else {
        super.onError(err, handler);
      }
    } else {
      super.onError(err, handler);
    }
  }
}
