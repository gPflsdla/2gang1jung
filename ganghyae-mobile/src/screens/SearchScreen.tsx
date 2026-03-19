import React, { useState, useRef, useEffect } from 'react';
// Import Platform to check environment
import { 
  View, 
  Text, 
  TextInput, 
  TouchableOpacity, 
  ScrollView, 
  SafeAreaView, 
  Dimensions, 
  KeyboardAvoidingView, 
  Platform 
} from 'react-native';

// Use a placeholder for MapView on web
const MapViewMock = ({ children, ...props }: any) => (
  <View {...props} style={[props.style, { backgroundColor: '#e2e8f0', justifyContent: 'center', alignItems: 'center' }]}>
    <Text className="text-slate-500 font-medium">지도는 모바일 기기에서 확인 가능합니다</Text>
    <Text className="text-slate-400 text-xs mt-2">Web Environment Placeholder</Text>
    {children}
  </View>
);

const MarkerMock = () => null;

const MapViewComponent = Platform.OS === 'web' ? MapViewMock : MapView;
const MarkerComponent = Platform.OS === 'web' ? MarkerMock : Marker;
import { Search, MapPin, Accessibility, PersonStanding, Star, Check, Navigation as NavIcon } from 'lucide-react-native';
import MapView, { Marker, PROVIDER_GOOGLE } from 'react-native-maps';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RootStackParamList } from '../types/navigation';

type SearchScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'Search'>;

const allLocations = [
  { id: 1, name: "중앙도서관", latitude: 33.4548, longitude: 126.5615 },
  { id: 2, name: "학생회관", latitude: 33.4535, longitude: 126.5605 },
  { id: 3, name: "본관", latitude: 33.4542, longitude: 126.5620 },
  { id: 4, name: "체육관", latitude: 33.4525, longitude: 126.5590 },
  { id: 5, name: "자연과학관", latitude: 33.4530, longitude: 126.5610 },
  { id: 6, name: "공과대학 4호관", latitude: 33.4520, longitude: 126.5600 },
];

export function SearchScreen() {
  const navigation = useNavigation<SearchScreenNavigationProp>();
  const [mode, setMode] = useState<'wheelchair' | 'normal'>('wheelchair');
  const [destination, setDestination] = useState("");
  const [origin, setOrigin] = useState("현재 위치 (공과대학 4호관)");
  const [favorites, setFavorites] = useState<string[]>([]);
  const [customPin, setCustomPin] = useState<{ latitude: number; longitude: number; name: string } | null>(null);
  const [originPin, setOriginPin] = useState<{ latitude: number; longitude: number; name: string } | null>({ latitude: 33.4520, longitude: 126.5600, name: "공과대학 4호관" });
  const [destinationPin, setDestinationPin] = useState<{ latitude: number; longitude: number; name: string } | null>(null);
  
  const [originSearch, setOriginSearch] = useState("");
  const [destSearch, setDestSearch] = useState("");
  const [originFocused, setOriginFocused] = useState(false);
  const [destFocused, setDestFocused] = useState(false);

  const filteredOriginLocations = allLocations.filter(loc => 
    loc.name.toLowerCase().includes(originSearch.toLowerCase())
  );
  const filteredDestLocations = allLocations.filter(loc => 
    loc.name.toLowerCase().includes(destSearch.toLowerCase())
  );

  const handleMapPress = (e: any) => {
    const { latitude, longitude } = e.nativeEvent.coordinate;
    setCustomPin({ latitude, longitude, name: `선택한 위치` });
  };

  const isFavorite = (name: string) => favorites.includes(name);
  const toggleFavorite = (name: string) => {
    setFavorites(prev => prev.includes(name) ? prev.filter(f => f !== name) : [...prev, name]);
  };

  const isWheelchairMode = mode === "wheelchair";

  return (
    <SafeAreaView className="flex-1 bg-slate-50">
      <View className="flex-1">
        {/* Map View */}
        <MapViewComponent
          provider={PROVIDER_GOOGLE}
          className="w-full h-full"
          initialRegion={{
            latitude: 33.4535,
            longitude: 126.5610,
            latitudeDelta: 0.01,
            longitudeDelta: 0.01,
          }}
          onPress={handleMapPress}
        >
          {originPin && (
            <MarkerComponent coordinate={{ latitude: originPin.latitude, longitude: originPin.longitude }} pinColor="#D4A5A5" title="출발지" />
          )}
          {destinationPin && (
            <MarkerComponent coordinate={{ latitude: destinationPin.latitude, longitude: destinationPin.longitude }} pinColor="#A5C4D4" title="도착지" />
          )}
          {customPin && (
            <MarkerComponent coordinate={{ latitude: customPin.latitude, longitude: customPin.longitude }} pinColor="red" title="선택한 위치" />
          )}
        </MapViewComponent>

        {/* Header Title with Emoji */}
        <View className="absolute top-12 left-0 right-0 z-10 px-4">
          <View className="bg-white/80 backdrop-blur-md rounded-3xl shadow-lg border border-white/50 p-4">
            <View className="flex-row items-center justify-center space-x-2">
              <Text className="text-xl">🗺️</Text>
              <Text className="text-base font-bold text-slate-700">학우들을 위한 내비 : 제주대학교</Text>
              <Text className="text-xl">🗺️</Text>
            </View>
          </View>
        </View>

        {/* Search Panel */}
        <View className="absolute top-32 left-0 right-0 z-10 px-4">
          <View className="bg-white/80 backdrop-blur-md rounded-3xl shadow-xl border border-white/50 p-5">
            <View className="space-y-3">
              {/* Origin Input */}
              <View className="relative">
                <View className="absolute left-3 top-1/2 -translate-y-1/2 w-8 h-8 rounded-full bg-[#D4A5A5] items-center justify-center z-20">
                  <MapPin size={16} color="white" />
                </View>
                <TextInput
                  className="w-full pl-14 pr-4 py-3 bg-white/90 rounded-2xl text-slate-700 text-sm font-medium border border-slate-200"
                  placeholder="출발지 검색..."
                  value={origin}
                  onChangeText={setOrigin}
                  onFocus={() => setOriginFocused(true)}
                  onBlur={() => setTimeout(() => setOriginFocused(false), 200)}
                />
              </View>

              {/* Destination Input */}
              <View className="relative">
                <View className="absolute left-3 top-1/2 -translate-y-1/2 w-8 h-8 rounded-full bg-[#A5C4D4] items-center justify-center z-20">
                  <MapPin size={16} color="white" />
                </View>
                <TextInput
                  className="w-full pl-14 pr-4 py-3 bg-white/90 rounded-2xl text-slate-700 text-sm font-medium border border-slate-200"
                  placeholder="도착지 검색..."
                  value={destination}
                  onChangeText={setDestination}
                  onFocus={() => setDestFocused(true)}
                  onBlur={() => setTimeout(() => setDestFocused(false), 200)}
                />
              </View>
            </View>

            {/* Mode Selection */}
            <View className="mt-6">
              <Text className="text-xs text-slate-500 mb-2 font-bold uppercase">경로 모드 선택</Text>
              <View className="flex-row space-x-3">
                <TouchableOpacity
                  onPress={() => setMode('wheelchair')}
                  className={`flex-1 p-3 rounded-2xl border-2 items-center ${mode === 'wheelchair' ? 'border-[#a5cfc9] bg-[#a5cfc9]/10' : 'border-slate-200 bg-white'}`}
                >
                  <Accessibility size={32} color={mode === 'wheelchair' ? '#7ab3ab' : '#94a3b8'} />
                  <Text className={`text-sm font-bold mt-1 ${mode === 'wheelchair' ? 'text-[#7ab3ab]' : 'text-slate-500'}`}>휠체어 모드</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  onPress={() => setMode('normal')}
                  className={`flex-1 p-3 rounded-2xl border-2 items-center ${mode === 'normal' ? 'border-[#e8c88a] bg-[#ffdfa3]/10' : 'border-slate-200 bg-white'}`}
                >
                  <PersonStanding size={32} color={mode === 'normal' ? '#9a8560' : '#94a3b8'} />
                  <Text className={`text-sm font-bold mt-1 ${mode === 'normal' ? 'text-[#9a8560]' : 'text-slate-500'}`}>일반 모드</Text>
                </TouchableOpacity>
              </View>
            </View>

            {/* Search Button */}
            <TouchableOpacity
              onPress={() => navigation.navigate('Route', { mode })}
              className={`w-full mt-6 py-4 rounded-2xl items-center flex-row justify-center ${isWheelchairMode ? 'bg-[#a5cfc9]' : 'bg-[#e8c88a]'}`}
            >
              <NavIcon size={20} color="white" className="mr-2" />
              <Text className="text-white font-bold text-base ml-2">경로 검색</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Favorite Section */}
        <View className="absolute bottom-8 left-0 right-0 px-4">
          <View className="bg-white/80 backdrop-blur-md rounded-2xl p-4 border border-white/50 shadow-lg">
            <View className="flex-row items-center mb-2">
              <Star size={16} color="#f59e0b" fill="#f59e0b" />
              <Text className="text-xs text-slate-500 font-bold ml-2 uppercase">즐겨찾는 장소</Text>
            </View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} className="flex-row space-x-3">
              {favorites.length > 0 ? (
                favorites.map((name, idx) => (
                  <TouchableOpacity key={idx} className="bg-white px-4 py-2 rounded-xl border border-slate-100 shadow-sm flex-row items-center space-x-2 mr-2">
                    <Star size={14} color="#f59e0b" fill="#f59e0b" />
                    <Text className="text-sm font-medium text-slate-600">{name}</Text>
                  </TouchableOpacity>
                ))
              ) : (
                <Text className="text-sm text-slate-400 py-2">즐겨찾기 목록이 비어 있습니다</Text>
              )}
            </ScrollView>
          </View>
        </View>
      </View>
    </SafeAreaView>
  );
}
